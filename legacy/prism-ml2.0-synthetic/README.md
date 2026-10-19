# PRISM ML

Two Decision Tree classifiers served by FastAPI.
See the deployment guide for the full step-by-step.

    python -m ml.make_datasets   # build synthetic training data
    python -m ml.train           # train + evaluate + save models/
    python -m tests.smoke_test   # sanity checks
    uvicorn app.main:app --reload
