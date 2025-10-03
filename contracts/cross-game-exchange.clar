;; Cross-Game Exchange Contract
;; Enables seamless exchange of gaming assets between different games
;; Provides automated exchange rates and cross-platform asset bridging

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u400))
(define-constant ERR-INVALID-EXCHANGE (err u401))
(define-constant ERR-ASSET-NOT-FOUND (err u402))
(define-constant ERR-INSUFFICIENT-BALANCE (err u403))
(define-constant ERR-EXCHANGE-CLOSED (err u404))
(define-constant ERR-INVALID-RATE (err u405))
(define-constant ERR-TRADE-NOT-FOUND (err u406))
(define-constant ERR-ALREADY-EXECUTED (err u407))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant EXCHANGE-FEE u300) ;; 3% in basis points
(define-constant MIN-TRADE-VALUE u100000) ;; 0.1 STX minimum

;; Exchange status
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-PAUSED u2)
(define-constant STATUS-COMPLETED u3)
(define-constant STATUS-CANCELLED u4)

;; System variables
(define-data-var next-trade-id uint u1)
(define-data-var total-trades uint u0)
(define-data-var exchange-active bool true)
(define-data-var total-volume uint u0)

;; Cross-game exchange rates mapping
(define-map exchange-rates
  { from-game: (string-ascii 50), to-game: (string-ascii 50), asset-category: uint }
  {
    rate: uint,
    last-updated: uint,
    volume-24h: uint,
    active: bool
  }
)

;; Trade listings for cross-game exchanges
(define-map trade-listings
  uint ;; trade-id
  {
    seller: principal,
    asset-id: uint,
    source-game: (string-ascii 50),
    target-game: (string-ascii 50),
    asking-price: uint,
    exchange-rate: uint,
    status: uint,
    created-at: uint,
    expires-at: uint
  }
)

;; Game compatibility mapping
(define-map game-compatibility
  { game-a: (string-ascii 50), game-b: (string-ascii 50) }
  {
    compatible: bool,
    bridge-fee: uint,
    last-updated: uint
  }
)

;; Asset bridge history
(define-map bridge-history
  uint ;; asset-id
  (list 50 { from-game: (string-ascii 50), to-game: (string-ascii 50), timestamp: uint })
)

;; Exchange statistics
(define-map exchange-stats
  (string-ascii 50) ;; game-id
  {
    total-imports: uint,
    total-exports: uint,
    volume-traded: uint,
    last-activity: uint
  }
)

;; Public function to list asset for cross-game exchange
(define-public (list-for-exchange
    (asset-id uint)
    (target-game (string-ascii 50))
    (asking-price uint)
    (duration uint))
  (let (
    (trade-id (var-get next-trade-id))
    (seller tx-sender)
    (current-height stacks-block-height)
  )
    ;; Validation checks
    (asserts! (var-get exchange-active) ERR-EXCHANGE-CLOSED)
    (asserts! (>= asking-price MIN-TRADE-VALUE) ERR-INVALID-EXCHANGE)
    (asserts! (> duration u0) ERR-INVALID-EXCHANGE)
    
    ;; Check asset ownership (would integrate with asset-tokenization contract)
    ;; For now, assume validation passes
    
    ;; Create trade listing
    (map-set trade-listings trade-id {
      seller: seller,
      asset-id: asset-id,
      source-game: "default-game", ;; Would be determined from asset metadata
      target-game: target-game,
      asking-price: asking-price,
      exchange-rate: u10000, ;; 1:1 rate as placeholder
      status: STATUS-ACTIVE,
      created-at: current-height,
      expires-at: (+ current-height duration)
    })
    
    ;; Update counters
    (var-set next-trade-id (+ trade-id u1))
    (var-set total-trades (+ (var-get total-trades) u1))
    
    (ok trade-id)
  )
)

;; Public function to execute cross-game asset swap
(define-public (execute-swap
    (trade-id uint)
    (buyer-asset-id uint))
  (let (
    (trade-data (unwrap! (map-get? trade-listings trade-id) ERR-TRADE-NOT-FOUND))
    (buyer tx-sender)
    (current-height stacks-block-height)
  )
    ;; Validation checks
    (asserts! (var-get exchange-active) ERR-EXCHANGE-CLOSED)
    (asserts! (is-eq (get status trade-data) STATUS-ACTIVE) ERR-ALREADY-EXECUTED)
    (asserts! (< current-height (get expires-at trade-data)) ERR-EXCHANGE-CLOSED)
    
    ;; Check game compatibility
    (asserts! (is-games-compatible 
                (get target-game trade-data) 
                "buyer-game") ;; Would be determined from buyer asset
              ERR-INVALID-EXCHANGE)
    
    ;; Execute the swap (simplified - would integrate with asset contracts)
    ;; Transfer seller's asset to buyer
    ;; Transfer buyer's asset to seller
    ;; Apply exchange rates and fees
    
    ;; Update trade status
    (map-set trade-listings trade-id 
      (merge trade-data {
        status: STATUS-COMPLETED
      })
    )
    
    ;; Update bridge history
    (update-bridge-history (get asset-id trade-data) 
                          (get source-game trade-data) 
                          (get target-game trade-data))
    
    ;; Update exchange statistics
    (update-exchange-stats (get source-game trade-data) (get asking-price trade-data))
    (update-exchange-stats (get target-game trade-data) (get asking-price trade-data))
    
    ;; Update total volume
    (var-set total-volume (+ (var-get total-volume) (get asking-price trade-data)))
    
    (ok true)
  )
)

;; Public function to calculate exchange rates
(define-public (calculate-exchange-rate
    (from-game (string-ascii 50))
    (to-game (string-ascii 50))
    (asset-category uint)
    (asset-value uint))
  (let (
    (rate-data (map-get? exchange-rates 
                        { from-game: from-game, to-game: to-game, asset-category: asset-category }))
  )
    (match rate-data
      rates (let (
        (base-rate (get rate rates))
        (fee-amount (/ (* asset-value EXCHANGE-FEE) u10000))
        (final-value (- (* asset-value base-rate) fee-amount))
      )
        (ok { 
          exchange-value: (/ final-value u10000),
          fee-amount: fee-amount,
          rate-used: base-rate
        })
      )
      (ok { 
        exchange-value: asset-value, ;; 1:1 default rate
        fee-amount: (/ (* asset-value EXCHANGE-FEE) u10000),
        rate-used: u10000
      })
    )
  )
)

;; Public function to bridge asset between games
(define-public (bridge-asset
    (asset-id uint)
    (from-game (string-ascii 50))
    (to-game (string-ascii 50)))
  (let (
    (bridge-fee (get-bridge-fee from-game to-game))
  )
    ;; Check compatibility and authorization
    (asserts! (var-get exchange-active) ERR-EXCHANGE-CLOSED)
    (asserts! (is-games-compatible from-game to-game) ERR-INVALID-EXCHANGE)
    
    ;; Pay bridge fee
    (try! (stx-transfer? bridge-fee tx-sender CONTRACT-OWNER))
    
    ;; Update bridge history
    (update-bridge-history asset-id from-game to-game)
    
    ;; Asset bridging logic would be implemented here
    ;; This would involve updating asset metadata and game registrations
    
    (ok true)
  )
)

;; Public function to set exchange rate (admin only)
(define-public (set-exchange-rate
    (from-game (string-ascii 50))
    (to-game (string-ascii 50))
    (asset-category uint)
    (rate uint))
  (begin
    ;; Only contract owner can set rates
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (> rate u0) ERR-INVALID-RATE)
    
    (map-set exchange-rates
      { from-game: from-game, to-game: to-game, asset-category: asset-category }
      {
        rate: rate,
        last-updated: stacks-block-height,
        volume-24h: u0,
        active: true
      }
    )
    
    (ok true)
  )
)

;; Public function to cancel trade listing
(define-public (cancel-trade (trade-id uint))
  (let (
    (trade-data (unwrap! (map-get? trade-listings trade-id) ERR-TRADE-NOT-FOUND))
  )
    ;; Check authorization
    (asserts! (or (is-eq tx-sender (get seller trade-data))
                  (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    
    ;; Update trade status
    (map-set trade-listings trade-id 
      (merge trade-data {
        status: STATUS-CANCELLED
      })
    )
    
    (ok true)
  )
)

;; Read-only function to get trade listing
(define-read-only (get-trade-listing (trade-id uint))
  (map-get? trade-listings trade-id)
)

;; Read-only function to get exchange rate
(define-read-only (get-exchange-rate (from-game (string-ascii 50)) (to-game (string-ascii 50)) (asset-category uint))
  (map-get? exchange-rates { from-game: from-game, to-game: to-game, asset-category: asset-category })
)

;; Read-only function to check game compatibility
(define-read-only (is-games-compatible (game-a (string-ascii 50)) (game-b (string-ascii 50)))
  (match (map-get? game-compatibility { game-a: game-a, game-b: game-b })
    compat-data (get compatible compat-data)
    false
  )
)

;; Read-only function to get bridge history
(define-read-only (get-bridge-history (asset-id uint))
  (default-to (list) (map-get? bridge-history asset-id))
)

;; Read-only function to get exchange statistics
(define-read-only (get-exchange-stats (game-id (string-ascii 50)))
  (map-get? exchange-stats game-id)
)

;; Read-only function to get system statistics
(define-read-only (get-system-stats)
  {
    total-trades: (var-get total-trades),
    next-trade-id: (var-get next-trade-id),
    exchange-active: (var-get exchange-active),
    total-volume: (var-get total-volume)
  }
)

;; Private function to get bridge fee between games
(define-private (get-bridge-fee (from-game (string-ascii 50)) (to-game (string-ascii 50)))
  (match (map-get? game-compatibility { game-a: from-game, game-b: to-game })
    compat-data (get bridge-fee compat-data)
    u50000 ;; Default bridge fee of 0.05 STX
  )
)

;; Private function to update bridge history
(define-private (update-bridge-history (asset-id uint) (from-game (string-ascii 50)) (to-game (string-ascii 50)))
  (let (
    (current-history (default-to (list) (map-get? bridge-history asset-id)))
    (new-entry { from-game: from-game, to-game: to-game, timestamp: stacks-block-height })
  )
    (map-set bridge-history asset-id 
      (unwrap-panic (as-max-len? (append current-history new-entry) u50)))
  )
)

;; Private function to update exchange statistics
(define-private (update-exchange-stats (game-id (string-ascii 50)) (trade-value uint))
  (let (
    (current-stats (default-to {
      total-imports: u0,
      total-exports: u0,
      volume-traded: u0,
      last-activity: u0
    } (map-get? exchange-stats game-id)))
  )
    (map-set exchange-stats game-id 
      (merge current-stats {
        volume-traded: (+ (get volume-traded current-stats) trade-value),
        last-activity: stacks-block-height
      })
    )
  )
)

