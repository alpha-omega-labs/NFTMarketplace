// SPDX-License-Identifier: MIT
// Developed by M for GenesisL1
 
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NFTMarketplace
 * @dev A marketplace that supports:
 *   - An Editor role (with certain admin capabilities).
 *   - A 'vault': NFTs sent directly to this contract (via safeTransferFrom)
 *       go to the vault and can be listed/mass listed by the Editor.
 *   - A configurable profit collector address.
 *   - Whitelisted NFT contracts only.
 *   - Two selling modes for NFTs: direct listing (fixed price) and auction.
 *   - Two adjustable fees (in basis points) for user-owned listings and auctions.
 *   - Editor can do a "mass listing" or "mass auction listing" of any vault NFTs 
 *       with default parameters.
 *   - A batch vault transfer function to send multiple NFTs from vault to 
 *       an external address, with a configurable max batch size.
 */
contract ExampleNFTMarketplace is IERC721Receiver, ReentrancyGuard {

    // ------------------------------------------------------------------------
    // EDITOR ROLE
    // ------------------------------------------------------------------------
    mapping(address => bool) private _editors;

    event EditorAdded(address indexed account);
    event EditorRemoved(address indexed account);

    modifier onlyEditor() {
        require(_editors[msg.sender], "Not an editor");
        _;
    }

    /**
     * @dev The deployer is the initial editor. 
     *      This contract has no separate 'owner' concept;
     *      you can add it if you like. 
     */
    constructor() {
        _editors[msg.sender] = true;
        emit EditorAdded(msg.sender);
        profitCollector = msg.sender; // default profit collector is deployer
    }

    function addEditor(address account) external onlyEditor {
        require(!_editors[account], "Already an editor");
        _editors[account] = true;
        emit EditorAdded(account);
    }

    function removeEditor(address account) external onlyEditor {
        require(_editors[account], "Not an editor");
        _editors[account] = false;
        emit EditorRemoved(account);
    }

    // ------------------------------------------------------------------------
    // WHITELIST
    // ------------------------------------------------------------------------
    mapping(address => bool) public whitelistedNFTs;

    event NFTWhitelisted(address indexed nftContract, bool status);

    /**
     * @dev Only whitelisted NFT contracts are allowed in marketplace
     */
    function setNFTWhitelisted(address nftContract, bool status) external onlyEditor {
        whitelistedNFTs[nftContract] = status;
        emit NFTWhitelisted(nftContract, status);
    }

    // ------------------------------------------------------------------------
    // PROFIT COLLECTOR
    // ------------------------------------------------------------------------
    address public profitCollector;

    event ProfitCollectorChanged(address indexed oldCollector, address indexed newCollector);

    /**
     * @dev Editor can change the profit collector (where proceeds from
     *      vault-owned NFT sales and listing/auction fees go).
     */
    function setProfitCollector(address newCollector) external onlyEditor {
        address old = profitCollector;
        profitCollector = newCollector;
        emit ProfitCollectorChanged(old, newCollector);
    }

    // ------------------------------------------------------------------------
    // FEE PARAMETERS (New)
    // ------------------------------------------------------------------------
    /**
     * @dev Fees are measured in basis points. 
     *      100 basis points = 1%.
     *      Maximum 10000 = 100%.
     */

    // Default is 1% for both listing and auction fees
    uint256 public listingFeeBps = 100;   // for user-owned fixed-price listings
    uint256 public auctionFeeBps = 100;   // for user-owned auctions

    event ListingFeeBpsChanged(uint256 oldFee, uint256 newFee);
    event AuctionFeeBpsChanged(uint256 oldFee, uint256 newFee);

    /**
     * @dev Editor can set the listing fee (in basis points) for user-owned fixed-price listings.
     *      e.g., 100 = 1%; 200 = 2%; 1000 = 10%; etc.
     */
    function setListingFeeBps(uint256 newFee) external onlyEditor {
        require(newFee <= 10000, "Fee too high");
        uint256 oldFee = listingFeeBps;
        listingFeeBps = newFee;
        emit ListingFeeBpsChanged(oldFee, newFee);
    }

    /**
     * @dev Editor can set the auction fee (in basis points) for user-owned auctions.
     */
    function setAuctionFeeBps(uint256 newFee) external onlyEditor {
        require(newFee <= 10000, "Fee too high");
        uint256 oldFee = auctionFeeBps;
        auctionFeeBps = newFee;
        emit AuctionFeeBpsChanged(oldFee, newFee);
    }

    // ------------------------------------------------------------------------
    // VAULT STORAGE
    // ------------------------------------------------------------------------
    struct VaultItem {
        address nftContract;
        uint256 tokenId;
        bool inVault;
    }

    VaultItem[] public vaultItems;

    mapping(address => mapping(uint256 => uint256)) public vaultIndex; 
    // 0-based index into vaultItems + 1 to handle 'not in vault' as 0

    function onERC721Received(
        address operator,
        address /*from*/,
        uint256 tokenId,
        bytes calldata /*data*/
    ) external override nonReentrant returns (bytes4) {
        // Only accept whitelisted NFT contracts
        require(whitelistedNFTs[msg.sender], "NFT contract not whitelisted");

        vaultItems.push(VaultItem({
            nftContract: msg.sender,
            tokenId: tokenId,
            inVault: true
        }));

        vaultIndex[msg.sender][tokenId] = vaultItems.length; 

        emit VaultTransferIn(operator, msg.sender, tokenId);

        return this.onERC721Received.selector;
    }

    event VaultTransferIn(address indexed operator, address indexed nftContract, uint256 tokenId);
    event VaultTransferOut(address indexed editor, address indexed nftContract, uint256 tokenId);

    function vaultTransferOut(
        address nftContract, 
        uint256 tokenId, 
        address to
    ) external onlyEditor {
        uint256 idxPlusOne = vaultIndex[nftContract][tokenId];
        require(idxPlusOne != 0, "Not in vault");
        uint256 realIndex = idxPlusOne - 1;
        require(vaultItems[realIndex].inVault, "Already removed");

        vaultItems[realIndex].inVault = false;
        vaultIndex[nftContract][tokenId] = 0;

        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
        emit VaultTransferOut(msg.sender, nftContract, tokenId);
    }

    // ------------------------------------------------------------------------
    // BATCH VAULT TRANSFER
    // ------------------------------------------------------------------------
    uint256 public maxVaultBatchTransferSize = 100;

    event MaxVaultBatchTransferSizeChanged(uint256 oldSize, uint256 newSize);

    function setMaxVaultBatchTransferSize(uint256 newSize) external onlyEditor {
        uint256 oldSize = maxVaultBatchTransferSize;
        maxVaultBatchTransferSize = newSize;
        emit MaxVaultBatchTransferSizeChanged(oldSize, newSize);
    }

    function vaultTransferOutBatch(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds,
        address to
    ) external onlyEditor {
        require(
            nftContracts.length == tokenIds.length,
            "Length mismatch"
        );
        require(
            nftContracts.length <= maxVaultBatchTransferSize,
            "Exceeds max batch size"
        );

        for (uint256 i = 0; i < nftContracts.length; i++) {
            address nftContract = nftContracts[i];
            uint256 tokenId = tokenIds[i];

            uint256 idxPlusOne = vaultIndex[nftContract][tokenId];
            require(idxPlusOne != 0, "Token not in vault");
            uint256 realIndex = idxPlusOne - 1;
            require(vaultItems[realIndex].inVault, "Token already removed");

            vaultItems[realIndex].inVault = false;
            vaultIndex[nftContract][tokenId] = 0;

            IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
            emit VaultTransferOut(msg.sender, nftContract, tokenId);
        }
    }

    // ------------------------------------------------------------------------
    // LISTINGS (FIXED PRICE)
    // ------------------------------------------------------------------------
    struct Listing {
        address seller;       // user or 'address(this)' if from vault
        address nftContract;
        uint256 tokenId;
        uint256 price;        // in native coin
        bool active;
    }

    mapping(address => mapping(uint256 => Listing)) public listings;

    event Listed(address indexed seller, address indexed nftContract, uint256 indexed tokenId, uint256 price);
    event ListingCancelled(address indexed seller, address indexed nftContract, uint256 indexed tokenId);
    event Purchased(address indexed buyer, address indexed nftContract, uint256 indexed tokenId, uint256 price);

    uint256 public defaultVaultListingPrice = 100 ether; // example default

    function setDefaultVaultListingPrice(uint256 newPrice) external onlyEditor {
        defaultVaultListingPrice = newPrice;
    }

    function massListVaultTokens() external onlyEditor {
        for (uint256 i = 0; i < vaultItems.length; i++) {
            if (vaultItems[i].inVault) {
                address nftContract = vaultItems[i].nftContract;
                uint256 tokenId = vaultItems[i].tokenId;

                if(!listings[nftContract][tokenId].active) {
                    listings[nftContract][tokenId] = Listing({
                        seller: address(this),
                        nftContract: nftContract,
                        tokenId: tokenId,
                        price: defaultVaultListingPrice,
                        active: true
                    });
                    emit Listed(address(this), nftContract, tokenId, defaultVaultListingPrice);
                }
            }
        }
    }

    function listVaultToken(address nftContract, uint256 tokenId, uint256 price) external onlyEditor {
        uint256 idxPlusOne = vaultIndex[nftContract][tokenId];
        require(idxPlusOne != 0, "Not in vault");
        uint256 realIndex = idxPlusOne - 1;
        require(vaultItems[realIndex].inVault, "Not in vault");

        require(!listings[nftContract][tokenId].active, "Already listed");

        listings[nftContract][tokenId] = Listing({
            seller: address(this),
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit Listed(address(this), nftContract, tokenId, price);
    }

    function listToken(address nftContract, uint256 tokenId, uint256 price)
        external
        payable
        nonReentrant
    {
        require(whitelistedNFTs[nftContract], "NFT contract not whitelisted");
        require(price > 0, "Invalid price");

        IERC721 tokenInterface = IERC721(nftContract);
        require(tokenInterface.ownerOf(tokenId) == msg.sender, "Not NFT owner");

        // Listing fee = (price * listingFeeBps) / 10000
        uint256 fee = (price * listingFeeBps) / 10000;
        require(msg.value >= fee, "Insufficient listing fee");

        // Transfer fee to profitCollector
        if (fee > 0) {
            (bool sent,) = payable(profitCollector).call{value: fee}("");
            require(sent, "Fee transfer failed");
        }

        // Transfer NFT from user to marketplace
        tokenInterface.safeTransferFrom(msg.sender, address(this), tokenId);

        listings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true
        });

        emit Listed(msg.sender, nftContract, tokenId, price);

        // Refund leftover if any
        uint256 leftover = msg.value - fee;
        if (leftover > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: leftover}("");
            require(refunded, "Refund leftover failed");
        }
    }

    function buyToken(address nftContract, uint256 tokenId)
        external
        payable
        nonReentrant
    {
        Listing storage lst = listings[nftContract][tokenId];
        require(lst.active, "Not listed for sale");
        require(msg.value == lst.price, "Incorrect payment amount");

        lst.active = false;

        address seller = lst.seller;
        if (seller == address(this)) {
            // from vault => all proceeds to profitCollector
            (bool sent,) = payable(profitCollector).call{value: msg.value}("");
            require(sent, "Vault proceeds transfer failed");

            // remove from vault
            uint256 idxPlusOne = vaultIndex[nftContract][tokenId];
            if (idxPlusOne != 0) {
                uint256 realIndex = idxPlusOne - 1;
                if (vaultItems[realIndex].inVault) {
                    vaultItems[realIndex].inVault = false;
                    vaultIndex[nftContract][tokenId] = 0;
                }
            }
        } else {
            // user => proceeds to user
            (bool sent2,) = payable(seller).call{value: msg.value}("");
            require(sent2, "User proceeds transfer failed");
        }

        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);

        emit Purchased(msg.sender, nftContract, tokenId, lst.price);
    }

    function cancelListing(address nftContract, uint256 tokenId) external nonReentrant {
        Listing storage lst = listings[nftContract][tokenId];
        require(lst.active, "Listing not active");
        
        bool isVaultItem = (lst.seller == address(this));
        if (isVaultItem) {
            require(_editors[msg.sender], "Vault listing: only Editor can cancel");
            lst.active = false;
            emit ListingCancelled(msg.sender, nftContract, tokenId);
        } else {
            require(lst.seller == msg.sender, "Not your listing");
            lst.active = false;
            emit ListingCancelled(msg.sender, nftContract, tokenId);

            IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
        }
    }

    // ------------------------------------------------------------------------
    // AUCTIONS
    // ------------------------------------------------------------------------
    struct Auction {
        address seller;         // user or address(this) if from vault
        address nftContract;
        uint256 tokenId;

        uint256 initialPrice;
        uint256 minStep;
        uint256 maxBids; 
        uint256 bidCount;
        address highestBidder;
        uint256 highestBid;
        bool active;
    }

    mapping(address => mapping(uint256 => Auction)) public auctions;

    event AuctionCreated(
        address indexed seller, 
        address indexed nftContract, 
        uint256 indexed tokenId, 
        uint256 initialPrice, 
        uint256 minStep, 
        uint256 maxBids
    );
    event AuctionBidPlaced(
        address indexed bidder, 
        address indexed nftContract, 
        uint256 indexed tokenId, 
        uint256 bid
    );
    event AuctionEnded(
        address indexed winner, 
        address indexed nftContract, 
        uint256 indexed tokenId, 
        uint256 finalPrice
    );
    event AuctionCancelled(
        address indexed seller, 
        address indexed nftContract, 
        uint256 indexed tokenId
    );

    uint256 public defaultAuctionInitialPrice = 100 ether;
    uint256 public defaultAuctionMinStep = 0.1 ether;
    uint256 public defaultAuctionMaxBids = 10;

    function setDefaultAuctionParams(
        uint256 initPrice, 
        uint256 step, 
        uint256 bids
    ) external onlyEditor {
        defaultAuctionInitialPrice = initPrice;
        defaultAuctionMinStep = step;
        defaultAuctionMaxBids = bids;
    }

    function massAuctionVaultTokens() external onlyEditor {
        for (uint256 i = 0; i < vaultItems.length; i++) {
            if (vaultItems[i].inVault) {
                address nftContract = vaultItems[i].nftContract;
                uint256 tokenId = vaultItems[i].tokenId;

                if (!auctions[nftContract][tokenId].active) {
                    auctions[nftContract][tokenId] = Auction({
                        seller: address(this),
                        nftContract: nftContract,
                        tokenId: tokenId,
                        initialPrice: defaultAuctionInitialPrice,
                        minStep: defaultAuctionMinStep,
                        maxBids: defaultAuctionMaxBids,
                        bidCount: 0,
                        highestBidder: address(0),
                        highestBid: 0,
                        active: true
                    });
                    emit AuctionCreated(
                        address(this), 
                        nftContract, 
                        tokenId, 
                        defaultAuctionInitialPrice, 
                        defaultAuctionMinStep, 
                        defaultAuctionMaxBids
                    );
                }
            }
        }
    }

    function createVaultAuction(
        address nftContract, 
        uint256 tokenId, 
        uint256 initPrice, 
        uint256 step, 
        uint256 bids
    ) external onlyEditor {
        uint256 idxPlusOne = vaultIndex[nftContract][tokenId];
        require(idxPlusOne != 0, "Not in vault");
        uint256 realIndex = idxPlusOne - 1;
        require(vaultItems[realIndex].inVault, "Not in vault");
        require(!auctions[nftContract][tokenId].active, "Already in auction");

        auctions[nftContract][tokenId] = Auction({
            seller: address(this),
            nftContract: nftContract,
            tokenId: tokenId,
            initialPrice: initPrice,
            minStep: step,
            maxBids: bids,
            bidCount: 0,
            highestBidder: address(0),
            highestBid: 0,
            active: true
        });

        emit AuctionCreated(address(this), nftContract, tokenId, initPrice, step, bids);
    }

    function createAuction(
        address nftContract, 
        uint256 tokenId, 
        uint256 initPrice, 
        uint256 step, 
        uint256 bids
    ) external payable nonReentrant {
        require(whitelistedNFTs[nftContract], "NFT not whitelisted");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(!auctions[nftContract][tokenId].active, "Already in auction");
        require(initPrice > 0 && bids > 0, "Invalid auction params");

        // Auction listing fee = (initPrice * auctionFeeBps) / 10000
        uint256 fee = (initPrice * auctionFeeBps) / 10000;
        require(msg.value >= fee, "Insufficient listing fee");

        (bool sentFee, ) = payable(profitCollector).call{value: fee}("");
        require(sentFee, "Listing fee transfer failed");

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        auctions[nftContract][tokenId] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            initialPrice: initPrice,
            minStep: step,
            maxBids: bids,
            bidCount: 0,
            highestBidder: address(0),
            highestBid: 0,
            active: true
        });

        emit AuctionCreated(msg.sender, nftContract, tokenId, initPrice, step, bids);

        uint256 leftover = msg.value - fee;
        if (leftover > 0) {
            (bool refunded, ) = payable(msg.sender).call{value: leftover}("");
            require(refunded, "Refund leftover failed");
        }
    }

    function placeBid(address nftContract, uint256 tokenId) 
        external 
        payable
        nonReentrant
    {
        Auction storage auc = auctions[nftContract][tokenId];
        require(auc.active, "Auction not active");
        uint256 currentRequiredBid = (auc.bidCount == 0) 
            ? auc.initialPrice 
            : (auc.highestBid + auc.minStep);
        require(msg.value >= currentRequiredBid, "Bid too low");

        if (auc.bidCount > 0) {
            (bool refundSent, ) = payable(auc.highestBidder).call{value: auc.highestBid}("");
            require(refundSent, "Refund failed");
        }

        auc.highestBidder = msg.sender;
        auc.highestBid = msg.value;
        auc.bidCount++;

        emit AuctionBidPlaced(msg.sender, nftContract, tokenId, msg.value);

        if (auc.bidCount >= auc.maxBids) {
            _endAuctionInternal(nftContract, tokenId);
        }
    }

    function endAuction(address nftContract, uint256 tokenId) external nonReentrant {
        Auction storage auc = auctions[nftContract][tokenId];
        require(auc.active, "Auction not active");
        require(
            auc.bidCount >= auc.maxBids || _editors[msg.sender], 
            "Not enough bids or not an editor"
        );
        _endAuctionInternal(nftContract, tokenId);
    }

    function _endAuctionInternal(address nftContract, uint256 tokenId) internal {
        Auction storage auc = auctions[nftContract][tokenId];
        auc.active = false;

        if (auc.bidCount == 0) {
            // no bids => return NFT
            IERC721(nftContract).safeTransferFrom(address(this), auc.seller, tokenId);
            emit AuctionEnded(address(0), nftContract, tokenId, 0);
            return;
        }

        if (auc.seller == address(this)) {
            // from vault => proceeds to profitCollector
            (bool sent,) = payable(profitCollector).call{value: auc.highestBid}("");
            require(sent, "Transfer to profitCollector failed");

            // remove from vault
            uint256 idxPlusOne = vaultIndex[nftContract][tokenId];
            if (idxPlusOne != 0) {
                uint256 realIndex = idxPlusOne - 1;
                if (vaultItems[realIndex].inVault) {
                    vaultItems[realIndex].inVault = false;
                    vaultIndex[nftContract][tokenId] = 0;
                }
            }
        } else {
            // user => proceeds to user
            (bool sent2,) = payable(auc.seller).call{value: auc.highestBid}("");
            require(sent2, "Transfer to seller failed");
        }

        IERC721(nftContract).safeTransferFrom(address(this), auc.highestBidder, tokenId);

        emit AuctionEnded(auc.highestBidder, nftContract, tokenId, auc.highestBid);
    }

    function cancelAuction(address nftContract, uint256 tokenId) external nonReentrant {
        Auction storage auc = auctions[nftContract][tokenId];
        require(auc.active, "Auction not active");

        bool isVaultItem = (auc.seller == address(this));
        if (isVaultItem) {
            require(_editors[msg.sender], "Vault auction: only Editor can cancel");
        } else {
            require(auc.seller == msg.sender, "Not the auction's seller");
        }

        if (auc.bidCount > 0) {
            (bool refundSent, ) = payable(auc.highestBidder).call{value: auc.highestBid}("");
            require(refundSent, "Refund to highestBidder failed");
        }

        auc.active = false;
        IERC721(nftContract).safeTransferFrom(address(this), auc.seller, tokenId);

        emit AuctionCancelled(auc.seller, nftContract, tokenId);
    }
}
