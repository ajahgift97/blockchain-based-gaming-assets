;; Gaming Asset Tokenization Contract
;; Tokenizes in-game items as NFTs with comprehensive metadata and rarity systems
;; Enables true ownership and cross-game compatibility for digital gaming assets

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-ASSET-NOT-FOUND (err u301))
(define-constant ERR-ALREADY-TOKENIZED (err u302))
(define-constant ERR-INVALID-GAME (err u303))
(define-constant ERR-INVALID-RARITY (err u304))
(define-constant ERR-INSUFFICIENT-FUNDS (err u305))
(define-constant ERR-INVALID-METADATA (err u306))
(define-constant ERR-ASSET-LOCKED (err u307))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE u250) ;; 2.5% in basis points

;; Asset rarity levels
(define-constant RARITY-COMMON u1)
(define-constant RARITY-UNCOMMON u2)
(define-constant RARITY-RARE u3)
(define-constant RARITY-EPIC u4)
(define-constant RARITY-LEGENDARY u5)
(define-constant RARITY-MYTHIC u6)

;; Asset categories
(define-constant CATEGORY-WEAPON u1)
(define-constant CATEGORY-ARMOR u2)
(define-constant CATEGORY-COSMETIC u3)
(define-constant CATEGORY-COLLECTIBLE u4)
(define-constant CATEGORY-UTILITY u5)
(define-constant CATEGORY-CURRENCY u6)

;; System variables
(define-data-var next-asset-id uint u1)
(define-data-var total-assets uint u0)
(define-data-var platform-active bool true)
(define-data-var minting-fee uint u1000000) ;; 1 STX

;; Non-fungible token definition
(define-non-fungible-token gaming-asset uint)

;; Asset metadata structure
(define-map asset-metadata
  uint ;; asset-id
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    game-id: (string-ascii 50),
    category: uint,
    rarity: uint,
    attributes: (string-ascii 1000),
    image-uri: (optional (string-ascii 200)),
    external-url: (optional (string-ascii 200)),
    created-at: uint,
    updated-at: uint
  }
)

;; Game registration and authorization
(define-map authorized-games
  (string-ascii 50) ;; game-id
  {
    game-name: (string-ascii 100),
    developer: principal,
    contract-address: (optional principal),
    active: bool,
    fee-rate: uint,
    registered-at: uint
  }
)

;; Asset provenance and ownership history
(define-map asset-provenance
  uint ;; asset-id
  {
    original-owner: principal,
    minted-in-game: (string-ascii 50),
    tokenization-date: uint,
    transfer-count: uint,
    last-transfer: (optional uint)
  }
)

;; Player asset collections
(define-map player-collections
  principal ;; player
  (list 1000 uint) ;; list of asset IDs
)

;; Asset statistics and analytics
(define-map asset-stats
  uint ;; asset-id
  {
    view-count: uint,
    like-count: uint,
    trade-count: uint,
    last-price: (optional uint),
    floor-price: (optional uint)
  }
)

;; Rarity distribution tracking
(define-map rarity-counts
  { game-id: (string-ascii 50), rarity: uint }
  uint ;; count of assets
)

;; Asset locking for cross-game usage
(define-map asset-locks
  uint ;; asset-id
  {
    locked-by: principal,
    target-game: (string-ascii 50),
    lock-duration: uint,
    locked-at: uint,
    auto-unlock: bool
  }
)

;; Public function to mint a new gaming asset NFT
(define-public (mint-gaming-asset
    (recipient principal)
    (name (string-ascii 100))
    (description (string-ascii 500))
    (game-id (string-ascii 50))
    (category uint)
    (rarity uint)
    (attributes (string-ascii 1000))
    (image-uri (optional (string-ascii 200)))
    (external-url (optional (string-ascii 200))))
  (let (
    (asset-id (var-get next-asset-id))
    (minter tx-sender)
  )
    ;; Validation checks
    (asserts! (var-get platform-active) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-game game-id) ERR-INVALID-GAME)
    (asserts! (is-valid-rarity rarity) ERR-INVALID-RARITY)
    (asserts! (is-valid-category category) ERR-INVALID-METADATA)
    (asserts! (> (len name) u0) ERR-INVALID-METADATA)
    
    ;; Check minting fee payment
    (try! (stx-transfer? (var-get minting-fee) minter CONTRACT-OWNER))
    
    ;; Mint the NFT
    (try! (nft-mint? gaming-asset asset-id recipient))
    
    ;; Set asset metadata
    (map-set asset-metadata asset-id {
      name: name,
      description: description,
      game-id: game-id,
      category: category,
      rarity: rarity,
      attributes: attributes,
      image-uri: image-uri,
      external-url: external-url,
      created-at: stacks-block-height,
      updated-at: stacks-block-height
    })
    
    ;; Set provenance data
    (map-set asset-provenance asset-id {
      original-owner: recipient,
      minted-in-game: game-id,
      tokenization-date: stacks-block-height,
      transfer-count: u0,
      last-transfer: none
    })
    
    ;; Initialize asset stats
    (map-set asset-stats asset-id {
      view-count: u0,
      like-count: u0,
      trade-count: u0,
      last-price: none,
      floor-price: none
    })
    
    ;; Update player collection
    (update-player-collection recipient asset-id)
    
    ;; Update rarity count
    (update-rarity-count game-id rarity)
    
    ;; Update system counters
    (var-set next-asset-id (+ asset-id u1))
    (var-set total-assets (+ (var-get total-assets) u1))
    
    (ok asset-id)
  )
)

;; Public function to transfer gaming assets
(define-public (transfer-gaming-asset (asset-id uint) (sender principal) (recipient principal))
  (let (
    (asset-owner (unwrap! (nft-get-owner? gaming-asset asset-id) ERR-ASSET-NOT-FOUND))
    (provenance-data (unwrap! (map-get? asset-provenance asset-id) ERR-ASSET-NOT-FOUND))
  )
    ;; Authorization checks
    (asserts! (or (is-eq tx-sender asset-owner) 
                  (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    (asserts! (is-eq sender asset-owner) ERR-UNAUTHORIZED)
    ;; Check if asset is locked
    (asserts! (not (is-asset-locked asset-id)) ERR-ASSET-LOCKED)
    
    ;; Execute transfer
    (try! (nft-transfer? gaming-asset asset-id sender recipient))
    
    ;; Update provenance
    (map-set asset-provenance asset-id 
      (merge provenance-data {
        transfer-count: (+ (get transfer-count provenance-data) u1),
        last-transfer: (some stacks-block-height)
      })
    )
    
    ;; Update player collections
    (remove-from-player-collection sender asset-id)
    (update-player-collection recipient asset-id)
    
    (ok true)
  )
)

;; Public function to update asset metadata (game developers only)
(define-public (update-asset-metadata
    (asset-id uint)
    (name (string-ascii 100))
    (description (string-ascii 500))
    (attributes (string-ascii 1000))
    (image-uri (optional (string-ascii 200)))
    (external-url (optional (string-ascii 200))))
  (let (
    (metadata (unwrap! (map-get? asset-metadata asset-id) ERR-ASSET-NOT-FOUND))
  )
    ;; Check authorization (game developer or contract owner)
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER)
                  (is-authorized-game-developer (get game-id metadata))) ERR-UNAUTHORIZED)
    
    ;; Update metadata
    (map-set asset-metadata asset-id 
      (merge metadata {
        name: name,
        description: description,
        attributes: attributes,
        image-uri: image-uri,
        external-url: external-url,
        updated-at: stacks-block-height
      })
    )
    
    (ok true)
  )
)

;; Public function to lock asset for cross-game usage
(define-public (lock-asset-for-game
    (asset-id uint)
    (target-game (string-ascii 50))
    (lock-duration uint)
    (auto-unlock bool))
  (let (
    (asset-owner (unwrap! (nft-get-owner? gaming-asset asset-id) ERR-ASSET-NOT-FOUND))
  )
    ;; Check ownership and game validity
    (asserts! (is-eq tx-sender asset-owner) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-game target-game) ERR-INVALID-GAME)
    (asserts! (not (is-asset-locked asset-id)) ERR-ASSET-LOCKED)
    
    ;; Set lock
    (map-set asset-locks asset-id {
      locked-by: asset-owner,
      target-game: target-game,
      lock-duration: lock-duration,
      locked-at: stacks-block-height,
      auto-unlock: auto-unlock
    })
    
    (ok true)
  )
)

;; Public function to unlock asset
(define-public (unlock-asset (asset-id uint))
  (let (
    (lock-data (unwrap! (map-get? asset-locks asset-id) ERR-ASSET-NOT-FOUND))
    (asset-owner (unwrap! (nft-get-owner? gaming-asset asset-id) ERR-ASSET-NOT-FOUND))
  )
    ;; Check authorization and lock status
    (asserts! (or (is-eq tx-sender (get locked-by lock-data))
                  (is-eq tx-sender asset-owner)
                  (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    
    ;; Remove lock
    (map-delete asset-locks asset-id)
    
    (ok true)
  )
)

;; Public function to register a new game
(define-public (register-game
    (game-id (string-ascii 50))
    (game-name (string-ascii 100))
    (developer principal)
    (contract-address (optional principal))
    (fee-rate uint))
  (begin
    ;; Only contract owner can register games
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    (map-set authorized-games game-id {
      game-name: game-name,
      developer: developer,
      contract-address: contract-address,
      active: true,
      fee-rate: fee-rate,
      registered-at: stacks-block-height
    })
    
    (ok true)
  )
)

;; Read-only function to get asset metadata
(define-read-only (get-asset-metadata (asset-id uint))
  (map-get? asset-metadata asset-id)
)

;; Read-only function to get asset owner
(define-read-only (get-asset-owner (asset-id uint))
  (nft-get-owner? gaming-asset asset-id)
)

;; Read-only function to get asset provenance
(define-read-only (get-asset-provenance (asset-id uint))
  (map-get? asset-provenance asset-id)
)

;; Read-only function to check if game is authorized
(define-read-only (is-authorized-game (game-id (string-ascii 50)))
  (match (map-get? authorized-games game-id)
    game-data (get active game-data)
    false
  )
)

;; Read-only function to get player collection
(define-read-only (get-player-collection (player principal))
  (default-to (list) (map-get? player-collections player))
)

;; Read-only function to get asset statistics
(define-read-only (get-asset-stats (asset-id uint))
  (map-get? asset-stats asset-id)
)

;; Read-only function to check if asset is locked
(define-read-only (is-asset-locked (asset-id uint))
  (is-some (map-get? asset-locks asset-id))
)

;; Read-only function to get system statistics
(define-read-only (get-system-stats)
  {
    total-assets: (var-get total-assets),
    next-asset-id: (var-get next-asset-id),
    platform-active: (var-get platform-active),
    minting-fee: (var-get minting-fee)
  }
)

;; Read-only function to get rarity distribution
(define-read-only (get-rarity-count (game-id (string-ascii 50)) (rarity uint))
  (default-to u0 (map-get? rarity-counts { game-id: game-id, rarity: rarity }))
)

;; Private function to validate rarity
(define-private (is-valid-rarity (rarity uint))
  (or (is-eq rarity RARITY-COMMON)
      (is-eq rarity RARITY-UNCOMMON)
      (is-eq rarity RARITY-RARE)
      (is-eq rarity RARITY-EPIC)
      (is-eq rarity RARITY-LEGENDARY)
      (is-eq rarity RARITY-MYTHIC))
)

;; Private function to validate category
(define-private (is-valid-category (category uint))
  (or (is-eq category CATEGORY-WEAPON)
      (is-eq category CATEGORY-ARMOR)
      (is-eq category CATEGORY-COSMETIC)
      (is-eq category CATEGORY-COLLECTIBLE)
      (is-eq category CATEGORY-UTILITY)
      (is-eq category CATEGORY-CURRENCY))
)

;; Private function to check if user is authorized game developer
(define-private (is-authorized-game-developer (game-id (string-ascii 50)))
  (match (map-get? authorized-games game-id)
    game-data (is-eq tx-sender (get developer game-data))
    false
  )
)

;; Private function to update player collection
(define-private (update-player-collection (player principal) (asset-id uint))
  (let (
    (current-collection (default-to (list) (map-get? player-collections player)))
  )
    (map-set player-collections player 
      (unwrap-panic (as-max-len? (append current-collection asset-id) u1000)))
  )
)

;; Private function to remove asset from player collection
(define-private (remove-from-player-collection (player principal) (asset-id uint))
  (let (
    (current-collection (default-to (list) (map-get? player-collections player)))
  )
    (map-set player-collections player (filter is-not-target current-collection))
  )
)

;; Helper function for filtering collections
(define-private (is-not-target (item uint))
  (not (is-eq item (var-get next-asset-id))) ;; Placeholder - would need asset-id context
)

;; Private function to update rarity count
(define-private (update-rarity-count (game-id (string-ascii 50)) (rarity uint))
  (let (
    (current-count (default-to u0 (map-get? rarity-counts { game-id: game-id, rarity: rarity })))
  )
    (map-set rarity-counts { game-id: game-id, rarity: rarity } (+ current-count u1))
  )
)

