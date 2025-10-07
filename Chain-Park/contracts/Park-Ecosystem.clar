;; Blockchain-Based Parking Space Reservation and Management Platform Contract
;;
;; This smart contract implements a decentralized parking infrastructure that enables:
;; - Real-time parking spot registration and availability tracking
;; - Time-based reservations with automated payment processing
;; - Dynamic pricing models for different parking spot categories
;; - Reputation scoring for users based on parking history
;; - Revenue sharing between spot owners and platform
;; - Performance analytics for parking utilization optimization

;; System administrator principal
(define-constant contract-owner tx-sender)

;; Error code definitions for transaction failures
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-SPOT-NOT-FOUND (err u101))
(define-constant ERR-SPOT-OCCUPIED (err u102))
(define-constant ERR-SPOT-AVAILABLE (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-RESERVATION-EXISTS (err u105))
(define-constant ERR-RESERVATION-NOT-FOUND (err u106))
(define-constant ERR-RESERVATION-EXPIRED (err u107))
(define-constant ERR-INSUFFICIENT-BALANCE (err u108))
(define-constant ERR-INVALID-TIME (err u109))
(define-constant ERR-SPOT-DISABLED (err u110))
(define-constant ERR-ALREADY-CHECKED-OUT (err u111))
(define-constant ERR-INVALID-CATEGORY (err u112))
(define-constant ERR-INVALID-PARAMS (err u113))

;; Parking spot type classifications
(define-constant spot-type-standard u1)
(define-constant spot-type-accessible u2)
(define-constant spot-type-ev-charging u3)
(define-constant spot-type-premium u4)

;; Global configuration state variables
(define-data-var spot-id-counter uint u1)
(define-data-var reservation-id-counter uint u1)
(define-data-var session-id-counter uint u1)
(define-data-var platform-treasury uint u0)
(define-data-var base-rate-per-hour uint u1000000)
(define-data-var penalty-rate-per-hour uint u500000)
(define-data-var max-reservation-period uint u86400)

;; Primary parking spot registry with comprehensive metadata
(define-map parking-spots
  { spot-id: uint }
  {
    owner: principal,
    location: (string-ascii 100),
    spot-type: uint,
    hourly-rate: uint,
    is-occupied: bool,
    is-active: bool,
    occupant: (optional principal),
    check-in-time: (optional uint),
    reservation-id: (optional uint)
  }
)

;; Reservation ledger for booking management
(define-map reservations
  { reservation-id: uint }
  {
    customer: principal,
    spot-id: uint,
    start-time: uint,
    end-time: uint,
    total-cost: uint,
    is-active: bool,
    is-used: bool
  }
)

;; User wallet balances for prepaid parking credits
(define-map account-balances
  { account: principal }
  { balance: uint }
)

;; Historical parking session records for auditing
(define-map parking-sessions
  { session-id: uint }
  {
    user: principal,
    spot-id: uint,
    start-timestamp: uint,
    end-timestamp: (optional uint),
    final-cost: uint,
    is-complete: bool
  }
)

;; User activity metrics and reputation tracking
(define-map user-stats
  { user: principal }
  {
    sessions-count: uint,
    total-spent: uint,
    total-penalties: uint,
    reputation: uint
  }
)

;; Parking spot utilization and revenue analytics
(define-map spot-metrics
  { spot-id: uint }
  {
    sessions-hosted: uint,
    revenue-earned: uint,
    avg-duration: uint,
    last-maintenance: uint
  }
)

;; Query functions for retrieving parking spot information
(define-read-only (get-spot-info (spot-id uint))
  (map-get? parking-spots { spot-id: spot-id })
)

;; Retrieve reservation details by identifier
(define-read-only (get-reservation-info (reservation-id uint))
  (map-get? reservations { reservation-id: reservation-id })
)

;; Check user account balance with default zero fallback
(define-read-only (get-balance (account principal))
  (default-to u0 (get balance (map-get? account-balances { account: account })))
)

;; Get current blockchain height as timestamp proxy
(define-read-only (get-block-time)
  block-height
)

;; Calculate parking cost based on duration and spot rate
(define-read-only (calculate-cost (spot-id uint) (duration uint))
  (match (map-get? parking-spots { spot-id: spot-id })
    spot-data (let
      (
        (rate (get hourly-rate spot-data))
        (hours (/ (+ duration u3599) u3600))
      )
      (ok (* hours rate))
    )
    ERR-SPOT-NOT-FOUND
  )
)

;; Verify spot availability for given time window
(define-read-only (is-spot-available (spot-id uint) (start uint) (end uint))
  (match (map-get? parking-spots { spot-id: spot-id })
    spot-data (and
      (get is-active spot-data)
      (not (get is-occupied spot-data))
      (is-none (get reservation-id spot-data))
    )
    false
  )
)

;; Retrieve user parking history and statistics
(define-read-only (get-user-history (user principal))
  (map-get? user-stats { user: user })
)

;; Get performance metrics for specific parking spot
(define-read-only (get-spot-analytics (spot-id uint))
  (map-get? spot-metrics { spot-id: spot-id })
)

;; Query total platform treasury balance
(define-read-only (get-platform-balance)
  (var-get platform-treasury)
)

;; Get current system-wide base hourly rate
(define-read-only (get-base-rate)
  (var-get base-rate-per-hour)
)

;; Get current penalty rate for overstays
(define-read-only (get-penalty-rate)
  (var-get penalty-rate-per-hour)
)

;; Get maximum allowed reservation duration
(define-read-only (get-max-reservation-time)
  (var-get max-reservation-period)
)

;; Validate spot identifier is within acceptable range
(define-private (is-valid-spot-id (spot-id uint))
  (and (> spot-id u0) (<= spot-id u1000000))
)

;; Validate reservation identifier is within acceptable range
(define-private (is-valid-reservation-id (reservation-id uint))
  (and (> reservation-id u0) (<= reservation-id u1000000))
)

;; Verify location string meets length requirements
(define-private (is-valid-location (location (string-ascii 100)))
  (and (> (len location) u0) (<= (len location) u100))
)

;; Confirm spot type matches predefined categories
(define-private (is-valid-spot-type (spot-type uint))
  (or (is-eq spot-type spot-type-standard)
      (is-eq spot-type spot-type-accessible)
      (is-eq spot-type spot-type-ev-charging)
      (is-eq spot-type spot-type-premium))
)

;; Update user statistics after parking session completion
(define-private (record-user-activity (user principal) (cost uint) (penalty uint))
  (let
    (
      (current-stats (default-to 
        { sessions-count: u0, total-spent: u0, total-penalties: u0, reputation: u100 }
        (map-get? user-stats { user: user })
      ))
      (new-session-count (+ (get sessions-count current-stats) u1))
      (new-total-spent (+ (get total-spent current-stats) cost))
      (new-penalties (+ (get total-penalties current-stats) penalty))
      (reputation-factor (if (> penalty u0) u95 u105))
      (new-reputation (/ (* (get reputation current-stats) reputation-factor) u100))
      (capped-reputation (if (> new-reputation u200) u200 new-reputation))
    )
    (map-set user-stats { user: user }
      {
        sessions-count: new-session-count,
        total-spent: new-total-spent,
        total-penalties: new-penalties,
        reputation: capped-reputation
      }
    )
  )
)

;; Update spot analytics after each parking session
(define-private (record-spot-performance (spot-id uint) (revenue uint) (duration uint))
  (let
    (
      (current-metrics (default-to 
        { sessions-hosted: u0, revenue-earned: u0, avg-duration: u0, last-maintenance: u0 }
        (map-get? spot-metrics { spot-id: spot-id })
      ))
      (new-sessions (+ (get sessions-hosted current-metrics) u1))
      (new-revenue (+ (get revenue-earned current-metrics) revenue))
      (new-avg (/ (+ (* (get avg-duration current-metrics) (get sessions-hosted current-metrics)) duration) new-sessions))
    )
    (map-set spot-metrics { spot-id: spot-id }
      {
        sessions-hosted: new-sessions,
        revenue-earned: new-revenue,
        avg-duration: new-avg,
        last-maintenance: (get last-maintenance current-metrics)
      }
    )
  )
)

;; Register a new parking spot with location and pricing details
(define-public (register-spot (location (string-ascii 100)) (spot-type uint) (rate uint))
  (let
    (
      (new-spot-id (var-get spot-id-counter))
    )
    (asserts! (is-valid-location location) ERR-INVALID-PARAMS)
    (asserts! (is-valid-spot-type spot-type) ERR-INVALID-CATEGORY)
    (asserts! (> rate u0) ERR-INVALID-AMOUNT)
    
    (map-set parking-spots { spot-id: new-spot-id }
      {
        owner: tx-sender,
        location: location,
        spot-type: spot-type,
        hourly-rate: rate,
        is-occupied: false,
        is-active: true,
        occupant: none,
        check-in-time: none,
        reservation-id: none
      }
    )
    
    (var-set spot-id-counter (+ new-spot-id u1))
    (ok new-spot-id)
  )
)

;; Modify existing parking spot settings (owner only)
(define-public (update-spot (spot-id uint) (new-rate uint) (active-status bool))
  (begin
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-PARAMS)
    (asserts! (> new-rate u0) ERR-INVALID-AMOUNT)
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot-data (begin
        (asserts! (is-eq tx-sender (get owner spot-data)) ERR-NOT-AUTHORIZED)
        
        (map-set parking-spots { spot-id: spot-id }
          (merge spot-data { 
            hourly-rate: new-rate,
            is-active: active-status
          })
        )
        (ok true)
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; Deposit funds into user account for parking payments
(define-public (deposit-funds (amount uint))
  (let
    (
      (current-balance (get-balance tx-sender))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set account-balances { account: tx-sender }
      { balance: (+ current-balance amount) }
    )
    
    (var-set platform-treasury (+ (var-get platform-treasury) amount))
    
    (ok true)
  )
)

;; Withdraw available funds from user account
(define-public (withdraw-funds (amount uint))
  (let
    (
      (current-balance (get-balance tx-sender))
    )
    (asserts! (<= amount current-balance) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (map-set account-balances { account: tx-sender }
      { balance: (- current-balance amount) }
    )
    
    (var-set platform-treasury (- (var-get platform-treasury) amount))
    
    (as-contract (stx-transfer? amount tx-sender tx-sender))
  )
)

;; Create advance reservation for parking spot
(define-public (make-reservation (spot-id uint) (start-time uint) (duration uint))
  (let
    (
      (new-reservation-id (var-get reservation-id-counter))
      (end-time (+ start-time duration))
      (cost-result (calculate-cost spot-id duration))
    )
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-PARAMS)
    (asserts! (<= duration (var-get max-reservation-period)) ERR-INVALID-TIME)
    (asserts! (>= start-time (get-block-time)) ERR-INVALID-TIME)
    (asserts! (is-spot-available spot-id start-time end-time) ERR-SPOT-OCCUPIED)
    
    (match cost-result
      reservation-cost (begin
        (asserts! (>= (get-balance tx-sender) reservation-cost) ERR-INSUFFICIENT-BALANCE)
        
        (map-set account-balances { account: tx-sender }
          { balance: (- (get-balance tx-sender) reservation-cost) }
        )
        
        (map-set reservations { reservation-id: new-reservation-id }
          {
            customer: tx-sender,
            spot-id: spot-id,
            start-time: start-time,
            end-time: end-time,
            total-cost: reservation-cost,
            is-active: true,
            is-used: false
          }
        )
        
        (match (map-get? parking-spots { spot-id: spot-id })
          spot-data (map-set parking-spots { spot-id: spot-id }
            (merge spot-data { reservation-id: (some new-reservation-id) })
          )
          false
        )
        
        (var-set reservation-id-counter (+ new-reservation-id u1))
        (ok new-reservation-id)
      )
      err-code (err err-code)
    )
  )
)

;; Cancel existing reservation with partial refund
(define-public (cancel-reservation (reservation-id uint))
  (begin
    (asserts! (is-valid-reservation-id reservation-id) ERR-INVALID-PARAMS)
    
    (match (map-get? reservations { reservation-id: reservation-id })
      reservation-data (begin
        (asserts! (is-eq tx-sender (get customer reservation-data)) ERR-NOT-AUTHORIZED)
        (asserts! (get is-active reservation-data) ERR-RESERVATION-NOT-FOUND)
        (asserts! (not (get is-used reservation-data)) ERR-RESERVATION-NOT-FOUND)
        
        (let
          (
            (current-time (get-block-time))
            (start (get start-time reservation-data))
            (original-cost (get total-cost reservation-data))
            (refund (if (> start current-time)
                      (/ (* original-cost u80) u100)
                      u0))
          )
          
          (if (> refund u0)
            (map-set account-balances { account: tx-sender }
              { balance: (+ (get-balance tx-sender) refund) }
            )
            true
          )
          
          (map-set reservations { reservation-id: reservation-id }
            (merge reservation-data { is-active: false })
          )
          
          (match (map-get? parking-spots { spot-id: (get spot-id reservation-data) })
            spot-data (map-set parking-spots { spot-id: (get spot-id reservation-data) }
              (merge spot-data { reservation-id: none })
            )
            false
          )
          
          (ok refund)
        )
      )
      ERR-RESERVATION-NOT-FOUND
    )
  )
)

;; Check in to parking spot and start session
(define-public (check-in (spot-id uint))
  (begin
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-PARAMS)
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot-data (begin
        (asserts! (get is-active spot-data) ERR-SPOT-DISABLED)
        (asserts! (not (get is-occupied spot-data)) ERR-SPOT-OCCUPIED)
        
        (let
          (
            (current-time (get-block-time))
            (new-session-id (var-get session-id-counter))
            (has-reservation (is-some (get reservation-id spot-data)))
          )
          
          (if has-reservation
            (match (get reservation-id spot-data)
              res-id (match (map-get? reservations { reservation-id: res-id })
                res-data (begin
                  (asserts! (is-eq tx-sender (get customer res-data)) ERR-NOT-AUTHORIZED)
                  (asserts! (get is-active res-data) ERR-RESERVATION-EXPIRED)
                  (asserts! (<= (get start-time res-data) current-time) ERR-INVALID-TIME)
                  (asserts! (>= (get end-time res-data) current-time) ERR-RESERVATION-EXPIRED)
                  
                  (map-set reservations { reservation-id: res-id }
                    (merge res-data { is-used: true })
                  )
                  true
                )
                false
              )
              true
            )
            true
          )
          
          (map-set parking-sessions { session-id: new-session-id }
            {
              user: tx-sender,
              spot-id: spot-id,
              start-timestamp: current-time,
              end-timestamp: none,
              final-cost: u0,
              is-complete: false
            }
          )
          
          (map-set parking-spots { spot-id: spot-id }
            (merge spot-data {
              is-occupied: true,
              occupant: (some tx-sender),
              check-in-time: (some current-time)
            })
          )
          
          (var-set session-id-counter (+ new-session-id u1))
          (ok new-session-id)
        )
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; Check out from parking spot and process payment
(define-public (check-out (spot-id uint))
  (begin
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-PARAMS)
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot-data (begin
        (asserts! (get is-occupied spot-data) ERR-SPOT-AVAILABLE)
        (asserts! (is-eq (some tx-sender) (get occupant spot-data)) ERR-NOT-AUTHORIZED)
        
        (let
          (
            (checkout-time (get-block-time))
            (checkin-time (unwrap! (get check-in-time spot-data) ERR-INVALID-TIME))
            (duration (- checkout-time checkin-time))
            (cost-result (calculate-cost spot-id duration))
            (spot-owner (get owner spot-data))
          )
          
          (match cost-result
            session-cost (begin
              (let
                (
                  (user-balance (get-balance tx-sender))
                  (penalty (if (> session-cost user-balance) 
                            (* (var-get penalty-rate-per-hour) (/ (- session-cost user-balance) (get hourly-rate spot-data)))
                            u0))
                  (total-cost (+ session-cost penalty))
                  (owner-share (/ (* session-cost u90) u100))
                  (platform-fee (- session-cost owner-share))
                )
                
                (if (>= user-balance total-cost)
                  (begin
                    (map-set account-balances { account: tx-sender }
                      { balance: (- user-balance total-cost) }
                    )
                    
                    (map-set account-balances { account: spot-owner }
                      { balance: (+ (get-balance spot-owner) owner-share) }
                    )
                  )
                  (begin
                    (map-set account-balances { account: tx-sender }
                      { balance: u0 }
                    )
                    
                    (let ((partial-payment (/ (* user-balance u90) u100)))
                      (map-set account-balances { account: spot-owner }
                        { balance: (+ (get-balance spot-owner) partial-payment) }
                      )
                    )
                  )
                )
                
                (map-set parking-spots { spot-id: spot-id }
                  (merge spot-data {
                    is-occupied: false,
                    occupant: none,
                    check-in-time: none,
                    reservation-id: none
                  })
                )
                
                (record-user-activity tx-sender total-cost penalty)
                (record-spot-performance spot-id session-cost duration)
                
                (ok { total-cost: total-cost, session-duration: duration, penalty-applied: penalty })
              )
            )
            err-code (err err-code)
          )
        )
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; Emergency unlock for stuck parking spots (admin only)
(define-public (force-unlock (spot-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-spot-id spot-id) ERR-INVALID-PARAMS)
    
    (match (map-get? parking-spots { spot-id: spot-id })
      spot-data (begin
        (map-set parking-spots { spot-id: spot-id }
          (merge spot-data {
            is-occupied: false,
            occupant: none,
            check-in-time: none,
            reservation-id: none
          })
        )
        (ok true)
      )
      ERR-SPOT-NOT-FOUND
    )
  )
)

;; Update system-wide pricing parameters (admin only)
(define-public (adjust-rates (new-base-rate uint) (new-penalty-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> new-base-rate u0) ERR-INVALID-AMOUNT)
    (asserts! (> new-penalty-rate u0) ERR-INVALID-AMOUNT)
    
    (var-set base-rate-per-hour new-base-rate)
    (var-set penalty-rate-per-hour new-penalty-rate)
    (ok true)
  )
)

;; Set maximum reservation time limit (admin only)
(define-public (set-reservation-limit (max-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> max-duration u0) ERR-INVALID-TIME)
    
    (var-set max-reservation-period max-duration)
    (ok true)
  )
)