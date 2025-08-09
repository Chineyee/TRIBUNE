;; TRIBUNE - Decentralized Consensus Infrastructure
;; A Bitcoin-secured network for distributed decision-making and collective intelligence

;; Constants
(define-constant PROTOCOL_ADMIN tx-sender)
(define-constant ERR_UNAUTHORIZED_ACCESS (err u100))
(define-constant ERR_INITIATIVE_NOT_FOUND (err u101))
(define-constant ERR_DUPLICATE_CONSENSUS (err u102))
(define-constant ERR_CONSENSUS_PERIOD_EXPIRED (err u103))
(define-constant ERR_INSUFFICIENT_INFLUENCE (err u104))
(define-constant ERR_INVALID_CONSENSUS_DURATION (err u105))
(define-constant ERR_PROFILE_NOT_EXISTS (err u106))
(define-constant ERR_CONTENT_NOT_FOUND (err u107))
(define-constant ERR_INVALID_INITIATIVE_TYPE (err u108))
(define-constant ERR_INFLUENCE_THRESHOLD_NOT_MET (err u109))

;; Data Variables
(define-data-var initiative-sequence uint u0)
(define-data-var content-sequence uint u0)
(define-data-var minimum-influence-threshold uint u150)
(define-data-var consensus-duration uint u1440) ;; ~10 days in blocks
(define-data-var protocol-treasury uint u0)
(define-data-var participation-reward uint u3)

;; Initiative Types
(define-constant INITIATIVE_GOVERNANCE "governance")
(define-constant INITIATIVE_TREASURY "treasury")
(define-constant INITIATIVE_PROTOCOL "protocol")
(define-constant INITIATIVE_COMMUNITY "community")

;; Data Maps
(define-map protocol-initiatives
  uint
  {
    title: (string-ascii 120),
    description: (string-ascii 600),
    initiator: principal,
    activation-block: uint,
    expiration-block: uint,
    support-influence: uint,
    opposition-influence: uint,
    executed: bool,
    initiative-category: (string-ascii 25),
    execution-threshold: uint,
    quorum-required: uint
  }
)

(define-map consensus-participation
  {initiative-id: uint, participant: principal}
  {
    position: bool,
    influence-committed: uint,
    participation-block: uint
  }
)

(define-map participant-influence
  principal
  {
    base-influence: uint,
    earned-influence: uint,
    locked-influence: uint,
    last-activity: uint
  }
)

(define-map participant-identities
  principal
  {
    display-name: (string-ascii 60),
    description: (string-ascii 250),
    registration-block: uint,
    content-contributions: uint,
    consensus-participation-count: uint,
    influence-tier: uint
  }
)

(define-map protocol-content
  uint
  {
    contributor: principal,
    content-data: (string-ascii 600),
    creation-block: uint,
    endorsements: uint,
    linked-initiative: (optional uint),
    content-category: (string-ascii 30),
    influence-reward: uint
  }
)

;; Influence Management System
(define-public (initialize-protocol-influence (initial-amount uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED_ACCESS)
    (map-set participant-influence tx-sender {
      base-influence: initial-amount,
      earned-influence: u0,
      locked-influence: u0,
      last-activity: block-height
    })
    (ok true)
  )
)

(define-private (allocate-influence (participant principal) (amount uint) (influence-type (string-ascii 10)))
  (let (
    (current-influence (default-to {
      base-influence: u0,
      earned-influence: u0,
      locked-influence: u0,
      last-activity: u0
    } (map-get? participant-influence participant)))
  )
    (map-set participant-influence participant 
      (if (is-eq influence-type "earned")
        (merge current-influence {
          earned-influence: (+ (get earned-influence current-influence) amount),
          last-activity: block-height
        })
        (merge current-influence {
          base-influence: (+ (get base-influence current-influence) amount),
          last-activity: block-height
        })
      )
    )
    true
  )
)

(define-read-only (get-total-influence (participant principal))
  (let (
    (influence-data (default-to {
      base-influence: u0,
      earned-influence: u0,
      locked-influence: u0,
      last-activity: u0
    } (map-get? participant-influence participant)))
  )
    (+ (get base-influence influence-data) (get earned-influence influence-data))
  )
)

;; Participant Identity Management
(define-public (establish-identity (display-name (string-ascii 60)) (description (string-ascii 250)))
  (let ((current-block block-height))
    (begin
      (map-set participant-identities tx-sender {
        display-name: display-name,
        description: description,
        registration-block: current-block,
        content-contributions: u0,
        consensus-participation-count: u0,
        influence-tier: u1
      })
      (map-set participant-influence tx-sender {
        base-influence: u25,
        earned-influence: u0,
        locked-influence: u0,
        last-activity: current-block
      })
      (ok true)
    )
  )
)

(define-read-only (get-participant-identity (participant principal))
  (map-get? participant-identities participant)
)

(define-read-only (get-participant-influence-data (participant principal))
  (map-get? participant-influence participant)
)


(define-public (participate-in-consensus (initiative-id uint) (support-position bool) (influence-commitment uint))
  (let (
    (initiative (unwrap! (map-get? protocol-initiatives initiative-id) ERR_INITIATIVE_NOT_FOUND))
    (participant-total-influence (get-total-influence tx-sender))
    (current-block block-height)
  )
    (asserts! (<= current-block (get expiration-block initiative)) ERR_CONSENSUS_PERIOD_EXPIRED)
    (asserts! (>= participant-total-influence influence-commitment) ERR_INSUFFICIENT_INFLUENCE)
    (asserts! (is-none (map-get? consensus-participation {initiative-id: initiative-id, participant: tx-sender})) ERR_DUPLICATE_CONSENSUS)
    
    ;; Record consensus participation
    (map-set consensus-participation {initiative-id: initiative-id, participant: tx-sender} {
      position: support-position,
      influence-committed: influence-commitment,
      participation-block: current-block
    })
    
    ;; Update initiative consensus tracking
    (map-set protocol-initiatives initiative-id 
      (if support-position
        (merge initiative {support-influence: (+ (get support-influence initiative) influence-commitment)})
        (merge initiative {opposition-influence: (+ (get opposition-influence initiative) influence-commitment)})
      )
    )
    
    ;; Update participant metrics
    (let ((identity (unwrap! (get-participant-identity tx-sender) ERR_PROFILE_NOT_EXISTS)))
      (map-set participant-identities tx-sender 
        (merge identity {consensus-participation-count: (+ (get consensus-participation-count identity) u1)}))
    )
    
    ;; Reward participation
    (allocate-influence tx-sender (var-get participation-reward) "earned")
    (ok true)
  )
)

;; Content Contribution System
(define-public (contribute-content 
  (content-data (string-ascii 600)) 
  (linked-initiative (optional uint))
  (content-category (string-ascii 30)))
  (let (
    (content-id (+ (var-get content-sequence) u1))
    (participant-identity (unwrap! (get-participant-identity tx-sender) ERR_PROFILE_NOT_EXISTS))
    (influence-reward u4)
  )
    (map-set protocol-content content-id {
      contributor: tx-sender,
      content-data: content-data,
      creation-block: block-height,
      endorsements: u0,
      linked-initiative: linked-initiative,
      content-category: content-category,
      influence-reward: influence-reward
    })
    
    ;; Update contributor metrics
    (map-set participant-identities tx-sender 
      (merge participant-identity {content-contributions: (+ (get content-contributions participant-identity) u1)}))
    
    (var-set content-sequence content-id)
    (allocate-influence tx-sender influence-reward "earned")
    (ok content-id)
  )
)

(define-public (endorse-content (content-id uint))
  (let ((content (unwrap! (map-get? protocol-content content-id) ERR_CONTENT_NOT_FOUND)))
    (map-set protocol-content content-id (merge content {endorsements: (+ (get endorsements content) u1)}))
    (allocate-influence (get contributor content) u2 "earned")
    (ok true)
  )
)

;; Advanced Governance Features
(define-public (execute-initiative (initiative-id uint))
  (let (
    (initiative (unwrap! (map-get? protocol-initiatives initiative-id) ERR_INITIATIVE_NOT_FOUND))
    (total-participation (+ (get support-influence initiative) (get opposition-influence initiative)))
    (support-ratio (if (> total-participation u0) 
                    (/ (* (get support-influence initiative) u100) total-participation) 
                    u0))
  )
    (asserts! (> block-height (get expiration-block initiative)) ERR_CONSENSUS_PERIOD_EXPIRED)
    (asserts! (>= total-participation (get quorum-required initiative)) ERR_INFLUENCE_THRESHOLD_NOT_MET)
    (asserts! (>= support-ratio (get execution-threshold initiative)) ERR_INFLUENCE_THRESHOLD_NOT_MET)
    (asserts! (not (get executed initiative)) ERR_DUPLICATE_CONSENSUS)
    
    (map-set protocol-initiatives initiative-id (merge initiative {executed: true}))
    
    ;; Reward successful initiative completion
    (allocate-influence (get initiator initiative) u10 "earned")
    (ok true)
  )
)

;; Query Functions
(define-read-only (get-initiative-details (initiative-id uint))
  (map-get? protocol-initiatives initiative-id)
)

(define-read-only (get-consensus-record (initiative-id uint) (participant principal))
  (map-get? consensus-participation {initiative-id: initiative-id, participant: participant})
)

(define-read-only (get-content-details (content-id uint))
  (map-get? protocol-content content-id)
)

(define-read-only (get-initiative-count)
  (var-get initiative-sequence)
)

(define-read-only (get-content-count)
  (var-get content-sequence)
)

(define-read-only (get-protocol-treasury)
  (var-get protocol-treasury)
)

;; Administrative Functions
(define-public (adjust-influence-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED_ACCESS)
    (ok (var-set minimum-influence-threshold new-threshold))
  )
)

(define-public (modify-consensus-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED_ACCESS)
    (asserts! (> new-duration u0) ERR_INVALID_CONSENSUS_DURATION)
    (ok (var-set consensus-duration new-duration))
  )
)

(define-public (update-participation-reward (new-reward uint))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED_ACCESS)
    (ok (var-set participation-reward new-reward))
  )
)

(define-public (treasury-deposit (amount uint))
  (begin
    (var-set protocol-treasury (+ (var-get protocol-treasury) amount))
    (ok true)
  )
)