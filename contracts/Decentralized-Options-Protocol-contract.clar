;; Decentralized Options Protocol
;; An options trading platform built entirely on Clarity

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-asset-exists (err u102))
(define-constant err-asset-not-found (err u103))
(define-constant err-option-not-found (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-insufficient-collateral (err u106))
(define-constant err-invalid-parameters (err u107))
(define-constant err-option-expired (err u108))
(define-constant err-option-not-expired (err u109))
(define-constant err-option-not-exercisable (err u110))
(define-constant err-option-already-settled (err u111))
(define-constant err-option-not-liquidatable (err u112))
(define-constant err-already-exercised (err u113))
(define-constant err-oracle-error (err u114))
(define-constant err-price-too-old (err u115))
(define-constant err-min-collateral (err u116))
(define-constant err-invalid-expiry (err u117))
(define-constant err-invalid-option-type (err u118))
(define-constant err-invalid-option-style (err u119))
(define-constant err-option-in-grace-period (err u120))
(define-constant err-option-not-in-grace-period (err u121))
(define-constant err-position-not-found (err u122))
(define-constant err-invalid-position-state (err u123))
(define-constant err-emergency-shutdown (err u124))
(define-constant err-maintenance-margin-too-low (err u125))
(define-constant err-premium-too-small (err u126))
(define-constant err-unsupported-calculation (err u127))

;; Option types enumeration
;; 0 = Call, 1 = Put
(define-data-var option-types (list 2 (string-ascii 4)) (list "Call" "Put"))

;; Option styles enumeration
;; 0 = American, 1 = European
(define-data-var option-styles (list 2 (string-ascii 9)) (list "American" "European"))

;; Position states enumeration
;; 0 = Active, 1 = Exercised, 2 = Expired, 3 = Liquidated
(define-data-var position-states (list 4 (string-ascii 10)) (list "Active" "Exercised" "Expired" "Liquidated"))

;; Supported underlying assets
(define-map assets
  { asset-id: (string-ascii 20) }
  {
    name: (string-ascii 40),
    price-oracle: principal,
    token-contract: principal,
    decimals: uint,
    historical-volatility: uint, ;; Annualized volatility in basis points
    volatility-history: (list 30 uint), ;; Last 30 days of volatility data
    is-stx: bool, ;; STX is handled specially
    minimum-increment: uint, ;; Smallest tradable amount
    last-price: uint, ;; Latest price in STX with 8 decimals
    last-price-update: uint, ;; Block height of last price update
    risk-factor: uint, ;; Risk factor 1-100
    enabled: bool
  }
)

;; Options contracts
(define-map options
  { option-id: uint }
  {
    creator: principal,
    underlying-asset: (string-ascii 20),
    strike-price: uint, ;; In STX with 8 decimals
    expiry-height: uint,
    option-type: uint, ;; 0=Call, 1=Put
    option-style: uint, ;; 0=American, 1=European
    collateral-amount: uint,
    premium: uint, ;; In STX
    contract-size: uint, ;; Number of units of underlying
    creation-height: uint,
    settlement-price: (optional uint),
    is-settled: bool,
    settlement-height: (optional uint),
    collateral-token: (string-ascii 20), ;; Token used for collateral
    holder: (optional principal),
    is-exercised: bool,
    exercise-height: (optional uint),
    is-liquidated: bool,
    liquidation-height: (optional uint),
    iv-at-creation: uint, ;; Implied volatility at creation in basis points
    premium-calculation-method: (string-ascii 10) ;; "black-scholes" or "custom"
  }
)
