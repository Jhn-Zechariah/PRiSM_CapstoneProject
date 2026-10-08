# PRISM Real-Farm Machine Learning Labeling Protocol

**Project:** PRISM — IoT-Based Pig Thermal Stress Monitoring System  
**Purpose:** Ground-truth labeling for genuine farm-collected machine learning data  
**Target task:** Binary classification of pig heat-stress status  
**Labels:** `NORMAL`, `HEAT_STRESS`, `UNLABELED`  
**Protocol status:** Draft for farm validation and approval  
**Version:** 1.0

---

## 1. Purpose

This protocol defines how observations collected from the PRISM system and the pig farm will be assigned ground-truth labels for supervised machine learning.

The machine learning model will learn to distinguish between:

- `NORMAL`
- `HEAT_STRESS`

Observations for which the available evidence is insufficient or unreliable will be assigned:

- `UNLABELED`

`UNLABELED` is not a machine learning class. These observations will normally be excluded from supervised model training and used only for data-quality monitoring or later review.

The purpose of this protocol is to ensure that the machine learning target is based on genuine farm observations rather than labels generated from the same mathematical rules or sensor thresholds that the model is expected to learn.

---

## 2. Important Principle

The PRISM machine learning label must not be generated directly from a deterministic temperature, humidity, THI, or other numerical threshold.

For example, the following procedure must not be used as the ground-truth labeling method:

```text
If temperature > X:
    HEAT_STRESS
else:
    NORMAL