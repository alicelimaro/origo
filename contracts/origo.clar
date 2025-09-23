;; === Origo: Decentralized Reputation Protocol ===

;; === Constants ===
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-TAG-EXISTS (err u402))
(define-constant ERR-SELF-ATTESTATION (err u403))
(define-constant ERR-ALREADY-ATTESTED (err u404))
(define-constant ERR-TAG-NOT-FOUND (err u405))
(define-constant ERR-CANNOT-SLASH-ZERO (err u410))
(define-constant ERR-NO-REPUTATION (err u411))
(define-constant ERR-INVALID-TAG (err u412))
(define-constant ERR-NOT-INITIALIZED (err u413))
(define-constant ERR-INVALID-PRINCIPAL (err u414))

;; === State ===

(define-map identities
  { user: principal }
  { joined: bool }
)

(define-map tags
  { tag: (string-ascii 32) }
  { exists: bool }
)

(define-map attestations
  { from: principal, to: principal, tag: (string-ascii 32) }
  { exists: bool }
)

(define-map reputation
  { user: principal, tag: (string-ascii 32) }
  { count: uint }
)

(define-map admins
  { user: principal }
  { is-admin: bool }
)

(define-data-var tag-count uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var initialized bool false)

(define-map tag-list
  { index: uint }
  { tag: (string-ascii 32) }
)

;; === Helper Functions ===

(define-private (is-valid-principal (user principal))
  ;; Basic principal validation - ensure it's not a zero principal
  (not (is-eq user 'SP000000000000000000002Q6VF78))
)

(define-private (is-admin (user principal))
  (and
    (is-valid-principal user)
    (default-to false (get is-admin (map-get? admins { user: user })))
  )
)

(define-private (is-valid-tag (tag (string-ascii 32)))
  (and 
    (> (len tag) u0)
    (<= (len tag) u32)
  )
)

(define-private (tag-exists (tag (string-ascii 32)))
  (is-some (map-get? tags { tag: tag }))
)

;; === Initialization Function ===
(define-public (initialize)
  (let ((sender tx-sender))
    (begin
      (asserts! (not (var-get initialized)) ERR-UNAUTHORIZED)
      (asserts! (is-eq sender (var-get contract-owner)) ERR-UNAUTHORIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (map-set admins { user: sender } { is-admin: true })
      (var-set initialized true)
      (ok true)
    )
  )
)

;; === Public Functions ===

(define-public (register)
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (map-set identities { user: sender } { joined: true })
      (ok true)
    )
  )
)

(define-public (add-admin (new-admin principal))
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-principal new-admin) ERR-INVALID-PRINCIPAL)
      (asserts! (is-admin sender) ERR-UNAUTHORIZED)
      (map-set admins { user: new-admin } { is-admin: true })
      (ok true)
    )
  )
)

(define-public (remove-admin (admin-to-remove principal))
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-principal admin-to-remove) ERR-INVALID-PRINCIPAL)
      (asserts! (is-admin sender) ERR-UNAUTHORIZED)
      (asserts! (not (is-eq admin-to-remove (var-get contract-owner))) ERR-UNAUTHORIZED)
      (map-delete admins { user: admin-to-remove })
      (ok true)
    )
  )
)

(define-public (add-tag (tag (string-ascii 32)))
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      ;; Validate input
      (asserts! (is-valid-tag tag) ERR-INVALID-TAG)
      ;; Check admin permissions
      (asserts! (is-admin sender) ERR-UNAUTHORIZED)
      ;; Check if tag already exists
      (asserts! (not (tag-exists tag)) ERR-TAG-EXISTS)
      
      (let ((count (var-get tag-count)))
        (map-set tags { tag: tag } { exists: true })
        (map-set tag-list { index: count } { tag: tag })
        (var-set tag-count (+ count u1))
        (ok tag)
      )
    )
  )
)

(define-public (attest (to principal) (tag (string-ascii 32)))
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-principal to) ERR-INVALID-PRINCIPAL)
      ;; Validate input
      (asserts! (is-valid-tag tag) ERR-INVALID-TAG)
      ;; Self-attestation not allowed
      (asserts! (not (is-eq sender to)) ERR-SELF-ATTESTATION)
      ;; Tag must exist
      (asserts! (tag-exists tag) ERR-TAG-NOT-FOUND)
      ;; Check if already attested
      (asserts! (is-none (map-get? attestations { from: sender, to: to, tag: tag })) ERR-ALREADY-ATTESTED)
      
      ;; Record attestation
      (map-set attestations { from: sender, to: to, tag: tag } { exists: true })
      
      ;; Increment reputation
      (let (
        (current (default-to u0 (get count (map-get? reputation { user: to, tag: tag }))))
      )
        (map-set reputation { user: to, tag: tag } { count: (+ current u1) })
        (ok true)
      )
    )
  )
)

(define-public (slash (target-user principal) (tag (string-ascii 32)))
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-principal target-user) ERR-INVALID-PRINCIPAL)
      ;; Validate input
      (asserts! (is-valid-tag tag) ERR-INVALID-TAG)
      ;; Check admin permissions
      (asserts! (is-admin sender) ERR-UNAUTHORIZED)
      
      (match (map-get? reputation { user: target-user, tag: tag })
        some-rep
        (let ((rep (get count some-rep)))
          (asserts! (> rep u0) ERR-CANNOT-SLASH-ZERO)
          (map-set reputation { user: target-user, tag: tag } { count: (- rep u1) })
          (ok true)
        )
        ERR-NO-REPUTATION
      )
    )
  )
)

;; === Read-Only Functions ===

(define-read-only (get-reputation (user principal) (tag (string-ascii 32)))
  (begin
    (asserts! (is-valid-principal user) ERR-INVALID-PRINCIPAL)
    (ok (default-to u0 (get count (map-get? reputation { user: user, tag: tag }))))
  )
)

(define-read-only (get-tag-count)
  (ok (var-get tag-count))
)

(define-read-only (get-tag-by-index (index uint))
  (map-get? tag-list { index: index })
)

(define-read-only (is-registered (user principal))
  (and
    (is-valid-principal user)
    (is-some (map-get? identities { user: user }))
  )
)

(define-read-only (has-attested (from principal) (to principal) (tag (string-ascii 32)))
  (and
    (is-valid-principal from)
    (is-valid-principal to)
    (is-some (map-get? attestations { from: from, to: to, tag: tag }))
  )
)

(define-read-only (is-user-admin (target-user principal))
  (and
    (is-valid-principal target-user)
    (is-admin target-user)
  )
)

(define-read-only (get-contract-owner)
  (ok (var-get contract-owner))
)

(define-read-only (is-initialized)
  (ok (var-get initialized))
)