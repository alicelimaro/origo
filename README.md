# Origo: Decentralized Reputation Protocol (Clarity)

## Overview
This contract implements a simple reputation system:
- Admins manage allowed tags.
- Users can attest a tag to another user (once per from→to→tag).
- Admins can slash (decrement) a user’s reputation for a tag.
- Reputation is tracked per user per tag.

Initialization is required before use and must be performed by the contract owner.

## Storage
- identities: { user } -> { joined: bool } — set by register; used by is-registered.
- tags: { tag } -> { exists: bool } — registry of allowed tags.
- tag-list: { index } -> { tag } — append-only list for enumeration.
- tag-count: uint — number of tags added.
- attestations: { from, to, tag } -> { exists: bool } — prevents duplicate attestations.
- reputation: { user, tag } -> { count: uint } — per-user, per-tag reputation count.
- admins: { user } -> { is-admin: bool } — admin set.
- contract-owner: principal — initialized to tx-sender at deploy time.
- initialized: bool — must be true for most public functions.

## Validation and Access Control
- is-valid-principal(user): user must not be 'SP000000000000000000002Q6VF78'.
- is-admin(user): checks admins map.
- is-valid-tag(tag): 1..32 ASCII length.
- tag-exists(tag): checks tags map.
- Many public functions require:
  - initialized = true.
  - valid principals.
  - admin role for admin-only actions.

## Public Functions
- initialize(): Only callable once by contract-owner; marks initialized = true and adds the owner as admin. Returns (ok true).
- register(): Marks caller in identities as joined: true. Returns (ok true).
- add-admin(new-admin): Admin-only. Adds new-admin to admins. Returns (ok true).
- remove-admin(admin-to-remove): Admin-only. Cannot remove contract-owner. Deletes from admins. Returns (ok true).
- add-tag(tag): Admin-only. Validates tag, ensures it doesn’t already exist, appends to tag-list, increments tag-count. Returns (ok tag).
- attest(to, tag): Any caller. Validates principals and tag, disallows self-attestation, requires tag exists, enforces no duplicate from→to→tag. Records attestation and increments to’s reputation for tag. Returns (ok true).
- slash(target-user, tag): Admin-only. Validates principals/tag, requires an existing reputation entry with count > 0, then decrements by 1. Returns (ok true) or ERR-NO-REPUTATION.

## Read-Only Functions
- get-reputation(user, tag): (ok uint), defaults to 0 if absent.
- get-tag-count(): (ok uint).
- get-tag-by-index(index): (optional { tag }).
- is-registered(user): bool — true if identities has an entry for user.
- has-attested(from, to, tag): bool — true if that unique attestation exists.
- is-user-admin(target-user): bool — admin status.
- get-contract-owner(): (ok principal).
- is-initialized(): (ok bool).

## Error Codes
- ERR-UNAUTHORIZED: (err u401)
- ERR-TAG-EXISTS: (err u402)
- ERR-SELF-ATTESTATION: (err u403)
- ERR-ALREADY-ATTESTED: (err u404)
- ERR-TAG-NOT-FOUND: (err u405)
- ERR-CANNOT-SLASH-ZERO: (err u410)
- ERR-NO-REPUTATION: (err u411)
- ERR-INVALID-TAG: (err u412)
- ERR-NOT-INITIALIZED: (err u413)
- ERR-INVALID-PRINCIPAL: (err u414)

## Notes
- Tags can be enumerated using get-tag-count and get-tag-by-index for indices [0, tag-count).
- Reputation changes only via attest (+1) and slash (-1).
