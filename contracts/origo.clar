;; === Origo: Decentralized Reputation Protocol (Enhanced) ===

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
(define-constant ERR-INSUFFICIENT-REPUTATION (err u415))
(define-constant ERR-ATTESTATION-LIMIT-REACHED (err u416))
(define-constant ERR-INVALID-WEIGHT (err u417))

;; Minimum reputation required to give weighted attestations
(define-constant MIN-REPUTATION-TO-ATTEST u5)
;; Maximum attestations per user per day
(define-constant MAX-DAILY-ATTESTATIONS u10)
;; Blocks in a day (approximately)
(define-constant BLOCKS-PER-DAY u144)

;; === Enhanced State ===

(define-map identities
  { user: principal }
  { joined: bool, join-block: uint }
)

(define-map tags
  { tag: (string-ascii 32) }
  { exists: bool, weight-multiplier: uint }
)

(define-map attestations
  { from: principal, to: principal, tag: (string-ascii 32) }
  { exists: bool, weight: uint, block-height: uint }
)

(define-map reputation
  { user: principal, tag: (string-ascii 32) }
  { count: uint, weighted-score: uint, last-decay: uint }
)

(define-map admins
  { user: principal }
  { is-admin: bool }
)

;; Track daily attestation counts to prevent spam
(define-map daily-attestation-count
  { user: principal, day: uint }
  { count: uint }
)

;; Track user's total reputation across all tags for weighting
(define-map user-total-reputation
  { user: principal }
  { total: uint }
)

(define-data-var tag-count uint u0)
(define-data-var contract-owner principal tx-sender)
(define-data-var initialized bool false)

(define-map tag-list
  { index: uint }
  { tag: (string-ascii 32) }
)

;; === Enhanced Helper Functions ===

(define-private (is-valid-principal (user principal))
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

(define-private (get-current-day)
  (/ stacks-block-height BLOCKS-PER-DAY)
)

(define-private (calculate-attestation-weight (attester principal))
  (let (
    (total-rep (default-to u0 (get total (map-get? user-total-reputation { user: attester }))))
  )
    (if (>= total-rep MIN-REPUTATION-TO-ATTEST)
      (+ u1 (/ total-rep u10)) ;; Base weight 1 + bonus based on reputation
      u1 ;; Minimum weight for new users
    )
  )
)

(define-private (update-total-reputation (user principal) (tag (string-ascii 32)) (change int))
  (let (
    (current-total (default-to u0 (get total (map-get? user-total-reputation { user: user }))))
    (new-total (if (> change 0) 
                  (+ current-total (to-uint change))
                  (if (>= current-total (to-uint (- 0 change)))
                    (- current-total (to-uint (- 0 change)))
                    u0)))
  )
    (map-set user-total-reputation { user: user } { total: new-total })
  )
)

;; FIXED: Pure calculation function for read-only operations
(define-private (calculate-reputation-decay (user principal) (tag (string-ascii 32)))
  (match (map-get? reputation { user: user, tag: tag })
    some-rep
    (let (
      (current-score (get weighted-score some-rep))
      (last-decay (get last-decay some-rep))
      (blocks-since-decay (- stacks-block-height last-decay))
    )
      (if (> blocks-since-decay (* BLOCKS-PER-DAY u30)) ;; 30 days
        (let (
          (decay-factor (/ blocks-since-decay (* BLOCKS-PER-DAY u30)))
          (decayed-score (if (> current-score decay-factor) (- current-score decay-factor) u0))
        )
          decayed-score
        )
        current-score
      )
    )
    u0
  )
)

;; FIXED: Separate function for applying decay with state modification
(define-private (apply-reputation-decay (user principal) (tag (string-ascii 32)))
  (match (map-get? reputation { user: user, tag: tag })
    some-rep
    (let (
      (current-score (get weighted-score some-rep))
      (last-decay (get last-decay some-rep))
      (blocks-since-decay (- stacks-block-height last-decay))
    )
      (if (> blocks-since-decay (* BLOCKS-PER-DAY u30)) ;; 30 days
        (let (
          (decay-factor (/ blocks-since-decay (* BLOCKS-PER-DAY u30)))
          (decayed-score (if (> current-score decay-factor) (- current-score decay-factor) u0))
        )
          (map-set reputation { user: user, tag: tag } 
            { count: (get count some-rep), weighted-score: decayed-score, last-decay: stacks-block-height })
          decayed-score
        )
        current-score
      )
    )
    u0
  )
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

;; === Enhanced Public Functions ===

(define-public (register)
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (map-set identities { user: sender } { joined: true, join-block: stacks-block-height })
      (map-set user-total-reputation { user: sender } { total: u0 })
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

;; Enhanced add-tag function with weight multiplier
(define-public (add-tag (tag (string-ascii 32)))
  (add-tag-with-weight tag u1)
)

(define-public (add-tag-with-weight (tag (string-ascii 32)) (weight-multiplier uint))
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-tag tag) ERR-INVALID-TAG)
      (asserts! (is-admin sender) ERR-UNAUTHORIZED)
      (asserts! (not (tag-exists tag)) ERR-TAG-EXISTS)
      (asserts! (and (>= weight-multiplier u1) (<= weight-multiplier u10)) ERR-INVALID-WEIGHT)
      
      (let ((count (var-get tag-count)))
        (map-set tags { tag: tag } { exists: true, weight-multiplier: weight-multiplier })
        (map-set tag-list { index: count } { tag: tag })
        (var-set tag-count (+ count u1))
        (ok tag)
      )
    )
  )
)

(define-public (attest (to principal) (tag (string-ascii 32)))
  (let (
    (sender tx-sender)
    (current-day (get-current-day))
    (daily-count (default-to u0 (get count (map-get? daily-attestation-count { user: sender, day: current-day }))))
  )
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-principal to) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-tag tag) ERR-INVALID-TAG)
      (asserts! (not (is-eq sender to)) ERR-SELF-ATTESTATION)
      (asserts! (tag-exists tag) ERR-TAG-NOT-FOUND)
      (asserts! (is-none (map-get? attestations { from: sender, to: to, tag: tag })) ERR-ALREADY-ATTESTED)
      (asserts! (< daily-count MAX-DAILY-ATTESTATIONS) ERR-ATTESTATION-LIMIT-REACHED)
      
      (let (
        (attestation-weight (calculate-attestation-weight sender))
        (tag-info (unwrap-panic (map-get? tags { tag: tag })))
        (tag-multiplier (get weight-multiplier tag-info))
        (final-weight (* attestation-weight tag-multiplier))
        (current-rep (default-to { count: u0, weighted-score: u0, last-decay: stacks-block-height } 
                      (map-get? reputation { user: to, tag: tag })))
      )
        ;; Record attestation with weight
        (map-set attestations { from: sender, to: to, tag: tag } 
          { exists: true, weight: final-weight, block-height: stacks-block-height })
        
        ;; Update daily attestation count
        (map-set daily-attestation-count { user: sender, day: current-day } 
          { count: (+ daily-count u1) })
        
        ;; Update reputation with weighted score
        (map-set reputation { user: to, tag: tag } 
          { count: (+ (get count current-rep) u1), 
            weighted-score: (+ (get weighted-score current-rep) final-weight),
            last-decay: stacks-block-height })
        
        ;; Update total reputation
        (update-total-reputation to tag (to-int final-weight))
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
      (asserts! (is-valid-tag tag) ERR-INVALID-TAG)
      (asserts! (is-admin sender) ERR-UNAUTHORIZED)
      
      (match (map-get? reputation { user: target-user, tag: tag })
        some-rep
        (let (
          (current-weighted (get weighted-score some-rep))
          (current-count (get count some-rep))
        )
          (asserts! (> current-weighted u0) ERR-CANNOT-SLASH-ZERO)
          (let (
            ;; Fixed: Replace max function with conditional logic
            (ten-percent (/ current-weighted u10))
            (slash-amount (if (> ten-percent u1) ten-percent u1)) ;; Use 10% or minimum 1
            (new-weighted (if (> current-weighted slash-amount) (- current-weighted slash-amount) u0))
            (new-count (if (> current-count u0) (- current-count u1) u0))
          )
            (map-set reputation { user: target-user, tag: tag } 
              { count: new-count, weighted-score: new-weighted, last-decay: stacks-block-height })
            (update-total-reputation target-user tag (- 0 (to-int slash-amount)))
            (ok true)
          )
        )
        ERR-NO-REPUTATION
      )
    )
  )
)

;; FIXED: New public function to apply decay with state modification
(define-public (refresh-reputation-decay (user principal) (tag (string-ascii 32)))
  (let ((sender tx-sender))
    (begin
      (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
      (asserts! (is-valid-principal sender) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-principal user) ERR-INVALID-PRINCIPAL)
      (asserts! (is-valid-tag tag) ERR-INVALID-TAG)
      (ok (apply-reputation-decay user tag))
    )
  )
)

;; === Enhanced Read-Only Functions ===

;; Backward compatible - returns simple count
(define-read-only (get-reputation (user principal) (tag (string-ascii 32)))
  (begin
    (asserts! (is-valid-principal user) ERR-INVALID-PRINCIPAL)
    (ok (default-to u0 (get count (map-get? reputation { user: user, tag: tag }))))
  )
)

;; FIXED: Now uses pure calculation function without state modification
(define-read-only (get-weighted-reputation (user principal) (tag (string-ascii 32)))
  (begin
    (asserts! (is-valid-principal user) ERR-INVALID-PRINCIPAL)
    (ok (calculate-reputation-decay user tag))
  )
)

(define-read-only (get-user-total-reputation (user principal))
  (begin
    (asserts! (is-valid-principal user) ERR-INVALID-PRINCIPAL)
    (ok (default-to u0 (get total (map-get? user-total-reputation { user: user }))))
  )
)

(define-read-only (get-attestation-weight (from principal) (to principal) (tag (string-ascii 32)))
  (match (map-get? attestations { from: from, to: to, tag: tag })
    some-attestation (ok (some (get weight some-attestation)))
    (ok none)
  )
)

(define-read-only (get-daily-attestation-count (user principal))
  (let ((current-day (get-current-day)))
    (ok (default-to u0 (get count (map-get? daily-attestation-count { user: user, day: current-day }))))
  )
)

(define-read-only (get-tag-weight-multiplier (tag (string-ascii 32)))
  (match (map-get? tags { tag: tag })
    some-tag (ok (some (get weight-multiplier some-tag)))
    (ok none)
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

;; Additional helper read-only functions
(define-read-only (get-user-join-block (user principal))
  (match (map-get? identities { user: user })
    some-identity (ok (some (get join-block some-identity)))
    (ok none)
  )
)

(define-read-only (get-reputation-details (user principal) (tag (string-ascii 32)))
  (match (map-get? reputation { user: user, tag: tag })
    some-rep (ok (some { 
      count: (get count some-rep), 
      weighted-score: (get weighted-score some-rep),
      last-decay: (get last-decay some-rep)
    }))
    (ok none)
  )
)
