# Blockchain-Based Parking Space Reservation and Management Platform

## Overview

This smart contract implements a decentralized parking infrastructure on the Stacks blockchain, enabling transparent, automated parking spot management with real-time reservations, dynamic pricing, and reputation tracking.

## Key Features

- Real-time parking spot registration and availability tracking
- Time-based reservations with automated payment processing
- Dynamic pricing models for different parking spot categories
- Reputation scoring for users based on parking history
- Revenue sharing between spot owners and platform (90/10 split)
- Performance analytics for parking utilization optimization
- Emergency administrative controls

## Contract Architecture

### Data Structures

#### Parking Spots
Each parking spot contains:
- Owner principal
- Location (up to 100 ASCII characters)
- Spot type (standard, accessible, EV charging, premium)
- Hourly rate
- Occupancy status
- Active/inactive status
- Current occupant information
- Check-in timestamp
- Associated reservation ID

#### Reservations
Reservation records include:
- Customer principal
- Associated spot ID
- Start and end times
- Total cost
- Active status
- Usage status

#### User Accounts
User balances and statistics tracked:
- Prepaid account balance
- Total sessions completed
- Total amount spent
- Accumulated penalties
- Reputation score (0-200 range)

#### Parking Sessions
Historical session records:
- User principal
- Spot ID
- Start and end timestamps
- Final cost
- Completion status

#### Spot Metrics
Performance analytics per spot:
- Total sessions hosted
- Revenue generated
- Average parking duration
- Last maintenance timestamp

## Parking Spot Types

1. Standard (Type 1): Regular parking spaces
2. Accessible (Type 2): Handicap-accessible spaces
3. EV Charging (Type 3): Electric vehicle charging stations
4. Premium (Type 4): Premium/reserved parking areas

## Core Functions

### Spot Management

#### register-spot
Register a new parking spot with location and pricing details.

Parameters:
- location (string-ascii 100): Physical location description
- spot-type (uint): Category identifier (1-4)
- rate (uint): Hourly rate in microSTX

Returns: New spot ID

#### update-spot
Modify existing parking spot settings (owner only).

Parameters:
- spot-id (uint): Spot identifier
- new-rate (uint): Updated hourly rate
- active-status (bool): Enable/disable spot

Returns: Success boolean

### Account Management

#### deposit-funds
Deposit STX into user account for parking payments.

Parameters:
- amount (uint): Amount to deposit in microSTX

Returns: Success boolean

#### withdraw-funds
Withdraw available funds from user account.

Parameters:
- amount (uint): Amount to withdraw in microSTX

Returns: Transaction result

### Reservation System

#### make-reservation
Create advance reservation for a parking spot.

Parameters:
- spot-id (uint): Target parking spot
- start-time (uint): Reservation start block height
- duration (uint): Duration in blocks

Returns: Reservation ID

Limitations:
- Maximum reservation period enforced
- Must have sufficient account balance
- Spot must be available for requested timeframe

#### cancel-reservation
Cancel existing reservation with partial refund (80% if cancelled before start time).

Parameters:
- reservation-id (uint): Reservation to cancel

Returns: Refund amount

### Parking Operations

#### check-in
Start a parking session at a specific spot.

Parameters:
- spot-id (uint): Parking spot identifier

Returns: Session ID

Requirements:
- Spot must be active and available
- Valid reservation required if spot is reserved
- Reservation must be within valid time window

#### check-out
End parking session and process payment.

Parameters:
- spot-id (uint): Parking spot identifier

Returns: Object containing total cost, duration, and penalty

Payment Processing:
- 90% of base cost goes to spot owner
- 10% retained as platform fee
- Penalties applied for insufficient balance
- Automatic revenue distribution

### Administrative Functions

#### force-unlock
Emergency function to unlock stuck parking spots (contract owner only).

Parameters:
- spot-id (uint): Spot to unlock

Returns: Success boolean

#### adjust-rates
Update system-wide pricing parameters (contract owner only).

Parameters:
- new-base-rate (uint): New base hourly rate
- new-penalty-rate (uint): New penalty rate

Returns: Success boolean

#### set-reservation-limit
Set maximum reservation duration (contract owner only).

Parameters:
- max-duration (uint): Maximum duration in blocks

Returns: Success boolean

## Query Functions

### get-spot-info
Retrieve complete parking spot information.

### get-reservation-info
Get reservation details by ID.

### get-balance
Check user account balance.

### get-block-time
Get current blockchain height (used as timestamp).

### calculate-cost
Calculate parking cost based on duration and spot rate.

### is-spot-available
Verify spot availability for a given time window.

### get-user-history
Retrieve user parking statistics and reputation.

### get-spot-analytics
Get performance metrics for a specific parking spot.

### get-platform-balance
Query total platform treasury balance.

### get-base-rate
Get current system-wide base hourly rate.

### get-penalty-rate
Get current penalty rate for overstays.

### get-max-reservation-time
Get maximum allowed reservation duration.

## Error Codes

- ERR-NOT-AUTHORIZED (100): Unauthorized access attempt
- ERR-SPOT-NOT-FOUND (101): Invalid spot ID
- ERR-SPOT-OCCUPIED (102): Spot currently in use
- ERR-SPOT-AVAILABLE (103): Spot not occupied
- ERR-INVALID-AMOUNT (104): Invalid payment amount
- ERR-RESERVATION-EXISTS (105): Conflicting reservation
- ERR-RESERVATION-NOT-FOUND (106): Invalid reservation ID
- ERR-RESERVATION-EXPIRED (107): Reservation time passed
- ERR-INSUFFICIENT-BALANCE (108): Insufficient funds
- ERR-INVALID-TIME (109): Invalid timestamp
- ERR-SPOT-DISABLED (110): Spot inactive
- ERR-ALREADY-CHECKED-OUT (111): Session already completed
- ERR-INVALID-CATEGORY (112): Invalid spot type
- ERR-INVALID-PARAMS (113): Invalid parameters

## Reputation System

User reputation scores range from 0 to 200:
- Starting reputation: 100
- Penalty-free checkout: +5% reputation (capped at 200)
- Checkout with penalty: -5% reputation
- Reputation affects future platform privileges

## Revenue Model

- Spot owners receive 90% of parking fees
- Platform retains 10% as service fee
- Penalty fees applied for insufficient balance
- Automated distribution upon checkout

## Security Features

- Principal-based authentication
- Owner-only spot modifications
- Admin-only emergency controls
- Balance validation before operations
- Reservation conflict prevention
- Time-based validation

## Usage Example Flow

1. Spot owner registers parking space with `register-spot`
2. User deposits funds with `deposit-funds`
3. User creates reservation with `make-reservation`
4. User checks in at scheduled time with `check-in`
5. User completes parking and checks out with `check-out`
6. Payment automatically distributed to owner and platform
7. User statistics and spot metrics updated

## Development Considerations

- All monetary values in microSTX (1 STX = 1,000,000 microSTX)
- Block height used as timestamp proxy
- Maximum spot ID: 1,000,000
- Maximum reservation ID: 1,000,000
- Location string limited to 100 ASCII characters