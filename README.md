# NFTMarketplace Solidity Contract

by M for GenesisL1

## Contents
1. [Introduction](#introduction)
2. [Source Code](#source-code)
3. [Detailed Explanation](#detailed-explanation)
   - [Editor Role](#editor-role)
   - [Whitelist](#whitelist)
   - [Profit Collector](#profit-collector)
   - [Fee Parameters](#fee-parameters)
   - [Vault Storage and Transfer](#vault-storage-and-transfer)
   - [Listings (Fixed Price)](#listings-fixed-price)
   - [Auctions](#auctions)
4. [Security and Usage Notes](#security-and-usage-notes)
5. [Conclusion](#conclusion)

## Introduction

This document provides an in-depth discussion of the `NFTMarketplace.sol` smart contract. The contract is designed to function as a generic ERC721 NFT marketplace with specialized features, including:

- An Editor Role with administrative capabilities.
- A Vault mechanism, whereby any NFT transferred directly to the contract is stored under marketplace control.
- Support for whitelisted NFT contracts only.
- A profit collector address that receives proceeds from sales and fees.
- Two selling modes:
  - Fixed-price listings with a configurable listing fee.
  - Auctions with an adjustable fee, minimal bid increments, and a maximum number of bids.
- Batch transferring of vaulted NFTs to external addresses.
- Editor-driven bulk actions (e.g., mass listing, mass auctioning) for NFTs in the vault.

## Source Code

[View the source code here](https://github.com/alpha-omega-labs/NFTMarketplace/blob/main/marketplace.sol)

## Detailed Explanation

This section describes each feature of the contract in detail.

### Editor Role

- Maintains a private mapping `_editors` of addresses to booleans, indicating editor roles.
- The constructor grants the deployer editor status.
- The `onlyEditor` modifier ensures certain critical functions can only be called by an editor.
- Editor-specific functions include:
  - `addEditor(address)`
  - `removeEditor(address)`
  - `setNFTWhitelisted`
  - `setProfitCollector`
  - `setListingFeeBps`, `setAuctionFeeBps`
  - `vaultTransferOut` and `vaultTransferOutBatch`
  - `listVaultToken`, `massListVaultTokens`
  - `massAuctionVaultTokens`, `createVaultAuction`, etc.

### Whitelist

- The marketplace only works with NFTs from whitelisted contracts.
- Tracks whitelisted NFT contracts using `mapping(address => bool) public whitelistedNFTs`.
- The `setNFTWhitelisted(address,bool)` function (editor-only) toggles whitelisted status.
- Ensures only approved ERC721s can be deposited using `require(whitelistedNFTs[msg.sender])` in `onERC721Received`.

### Profit Collector

- `profitCollector` is an address that receives proceeds from:
  - Sales of NFTs owned by the vault.
  - Listing and auction fees from user-owned items.
- The address can be updated using `setProfitCollector` (editor-only).

### Fee Parameters

- `listingFeeBps` and `auctionFeeBps` store fees in basis points (100 bps = 1%).
- Default: 100 (1%). Configurable by an editor using:
  - `setListingFeeBps(uint256 newFee)`
  - `setAuctionFeeBps(uint256 newFee)`
- Maximum: 10000 (100%).

### Vault Storage and Transfer

- NFTs transferred to the contract trigger `onERC721Received`, storing them in a `VaultItem` struct array.
- The vault facilitates mass listing/auctioning or transfer out by editors.
- Functions include:
  - `vaultTransferOut` (transfers single NFT out of the vault).
  - `vaultTransferOutBatch` (handles multiple NFTs in one transaction).

### Listings (Fixed Price)

Two listing scenarios:
1. **Vault-owned listings:** Created by an editor. No listing fee applies. Proceeds go to the `profitCollector`.
2. **User-owned listings:** Users call `listToken`. A listing fee `(price × listingFeeBps) / 10000` is paid upfront. Proceeds go to the user upon sale.

- The `Listing` struct includes seller, nftContract, tokenId, price, and active status.
- Buyers call `buyToken`, paying the exact `price`.

### Auctions

- Auctions support:
  - `initialPrice` (minimum opening bid).
  - `minStep` (minimum increment above the highest bid).
  - `maxBids` (auction ends after `maxBids` valid bids).
- Managed using the `Auction` struct and `auctions[nftContract][tokenId]`.
- Functions include:
  - `createVaultAuction`: For vault-owned NFTs (no fee).
  - `createAuction`: For user-owned NFTs (fee applies).
  - `endAuction`: Ends auctions with `bidCount >= maxBids` or via editor action.
  - `cancelAuction`: Refunds the highest bidder and returns the NFT to the seller.

## Security and Usage Notes

- Uses `ReentrancyGuard` (OpenZeppelin) to prevent re-entrant calls.
- Only whitelisted NFT contracts can interact with the vault.
- Limits batch transfers to avoid overly large loops.
- Editor-controlled fees capped at 100% (10000 bps).

## Conclusion

The `NFTMarketplace` contract is a versatile ERC721 marketplace that supports fixed-price listings and auctions. Key features include:

1. NFTs transferred to the vault are automatically managed.
2. Editors can mass list or auction vault items.
3. Users can list or auction their own NFTs.
4. Buyers pay exact asking prices or bid with automatic refunds for outbid participants.
5. Proceeds go to the `profitCollector` (vault items) or the seller (user items).

