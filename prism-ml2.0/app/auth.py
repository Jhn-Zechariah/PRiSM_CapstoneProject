"""Authentication (Firebase ID token) and the admin role (custom claim).

The Flutter app already sends `Authorization: Bearer <Firebase ID token>`
(lib/core/services/ml_service.dart). Verifying a token needs only the Firebase project
ID (env PRISM_FIREBASE_PROJECT), not a service-account key. Fails CLOSED: if the
verifier cannot be set up, protected endpoints answer 503, never "allow".
Tokens are never logged.
"""
import logging
import os
import re

from fastapi import Depends, Header, HTTPException, Request

from app.settings import api_config

log = logging.getLogger("prism.api.auth")
_JWT_LIKE = re.compile(r"[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*")


def safe_reason(err):
    """Firebase's rejection reason (wrong project, used too early, expired, ...) with anything
    token-shaped removed, so it can be logged without leaking credentials."""
    return _JWT_LIKE.sub("[token removed]", str(err))[:300]


class AuthUnavailable(Exception):
    pass


def _public_keys_only_credential():
    """Verifying an ID token only downloads Google's PUBLIC signing keys, so no secret is
    needed. firebase-admin 7.x still asks for "application default credentials" when it
    builds its auth client, and fails with DefaultCredentialsError if none are set up.
    This credential satisfies that without any key. It cannot call privileged Firebase APIs."""
    from firebase_admin import credentials
    from google.auth.credentials import AnonymousCredentials

    class PublicKeysOnly(credentials.Base):
        def get_credential(self):
            return AnonymousCredentials()

    return PublicKeysOnly()


class FirebaseVerifier:
    def __init__(self):
        try:
            import firebase_admin
            from firebase_admin import auth
        except ImportError as e:
            raise AuthUnavailable("firebase-admin is not installed") from e
        if not firebase_admin._apps:
            project = os.environ.get("PRISM_FIREBASE_PROJECT")
            if not project:
                raise AuthUnavailable("PRISM_FIREBASE_PROJECT is not set")
            # Use a real service account only if one is configured; token checks don't need it.
            cred = None if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") else _public_keys_only_credential()
            firebase_admin.initialize_app(credential=cred, options={"projectId": project})
        self.project = firebase_admin.get_app().project_id
        log.info("verifying Firebase ID tokens for project %r", self.project)
        self._auth = auth

    def verify(self, token):
        # Tolerate a small clock difference between this server and Google, otherwise a
        # freshly issued token is rejected as "used too early".
        return self._auth.verify_id_token(token, clock_skew_seconds=api_config()["auth"]["clock_skew_seconds"])


def build_verifier():
    try:
        return FirebaseVerifier(), None
    except AuthUnavailable as e:
        log.warning("authentication not configured: %s", e)
        return None, str(e)


def _bearer(authorization):
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    return token.strip() if scheme.lower() == "bearer" and token.strip() else None


def current_user(request: Request, authorization: str = Header(default=None)):
    verifier = request.app.state.verifier
    if verifier is None:
        raise HTTPException(status_code=503, detail="authentication is not configured on this server")
    token = _bearer(authorization)
    if token is None:
        raise HTTPException(status_code=401, detail="missing bearer token",
                            headers={"WWW-Authenticate": "Bearer"})
    try:
        claims = verifier.verify(token)
    except Exception as e:                                    # never log the token itself
        log.warning("token rejected (%s): %s", type(e).__name__, safe_reason(e))
        raise HTTPException(status_code=401, detail="invalid or expired token",
                            headers={"WWW-Authenticate": "Bearer"}) from None
    return {"uid": claims.get("uid") or claims.get("user_id") or claims.get("sub"), "claims": claims}


def is_admin(user):
    a = api_config()["auth"]
    return user["claims"].get(a["admin_claim"]) == a["admin_value"]


def admin_user(user=Depends(current_user)):
    if not is_admin(user):
        log.info("admin access denied for uid=%s", user["uid"])
        raise HTTPException(status_code=403, detail="admin role required")
    return user
