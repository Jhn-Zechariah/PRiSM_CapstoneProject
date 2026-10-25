"""Grant or revoke the API admin role (Firebase custom claim). Run by a project owner:

  GOOGLE_APPLICATION_CREDENTIALS=/path/outside/repo/key.json \
  python -m app.admin_claims grant <firebase-uid>      # or: revoke <uid>, show <uid>

The user must sign in again (or refresh the token) before the new claim applies.
"""
import argparse

from app.settings import api_config


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("action", choices=["grant", "revoke", "show"])
    p.add_argument("uid")
    a = p.parse_args(argv)
    import firebase_admin
    from firebase_admin import auth
    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    cfg = api_config()["auth"]
    claims = dict(auth.get_user(a.uid).custom_claims or {})
    if a.action == "grant":
        claims[cfg["admin_claim"]] = cfg["admin_value"]
    elif a.action == "revoke":
        claims.pop(cfg["admin_claim"], None)
    if a.action != "show":
        auth.set_custom_user_claims(a.uid, claims)
    print(a.uid, claims)


if __name__ == "__main__":
    main()
