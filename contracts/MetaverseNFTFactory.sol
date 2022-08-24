// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./MetaverseNFT.sol";

/**
 * MetaverseNFT is a cloneable contract for your NFT collection.
 * It's adapted from OpenZeppeling ERC721 implementation upgradeable versions.
 * This is needed to make it possible to create clones that work via delegatecall
 * ! The constructor is replaced with initializer, too
 * This way, deployment costs about 350k gas instead of 4.5M.
 * 1. https://forum.openzeppelin.com/t/how-to-set-implementation-contracts-for-clones/6085/4
 * 2. https://github.com/OpenZeppelin/workshops/tree/master/02-contracts-clone/contracts/2-uniswap
 * 3. https://docs.openzeppelin.com/contracts/4.x/api/proxy
 */

contract MetaverseNFTFactory is Ownable {
    address public immutable proxyImplementation;
    IERC721 public earlyAccessPass;
    uint256 public maxAllowedAmount = 50 ether; // launch for free if your collection collects less than this amount
    uint256 public maxPerMintLimit;

    // bitmask params
    uint32 constant SHOULD_START_AT_ONE = 1 << 1;
    uint32 constant SHOULD_START_SALE = 1 << 2;
    uint32 constant SHOULD_LOCK_PAYOUT_CHANGE = 1 << 3;

    event NFTCreated(
        address indexed deployedAddress,
        address indexed creator,
        // creation parameters
        uint256 price,
        uint256 maxSupply,
        uint256 nReserved,
        string name,
        string symbol,
        bool shouldUseJsonExtension,
        bool startAtOne,
        bool shouldStartSale,
        bool shouldLockPayoutReceiver
    );

    modifier hasAccess(address creator) {
        // check that creator owns NFT
        require(
            address(earlyAccessPass) == address(0) ||
                earlyAccessPass.balanceOf(msg.sender) > 0,
            "MetaverseNFTFactory: Early Access Pass is required"
        );
        _;
    }

    modifier checkTotalAmount(uint256 amount) {
        require(
            amount < maxAllowedAmount,
            "MetaverseNFTFactory: Collection total amount is too high"
        );
        _;
    }

    constructor(address _earlyAccessPass) {
        proxyImplementation = address(new MetaverseNFT());

        earlyAccessPass = IERC721(_earlyAccessPass);

        maxPerMintLimit = MetaverseNFT(payable(proxyImplementation))
            .MAX_PER_MINT_LIMIT();

        emit NFTCreated(
            proxyImplementation,
            msg.sender,
            0,
            0,
            0,
            "IMPLEMENTATION",
            "IMPLEMENTATION",
            false,
            false,
            false,
            false
        );
    }

    function updateEarlyAccessPass(address _earlyAccessPass) public onlyOwner {
        earlyAccessPass = IERC721(_earlyAccessPass);
    }

    function setMaxPerMintLimit(uint256 _maxPerMintLimit) external onlyOwner {
        maxPerMintLimit = _maxPerMintLimit;
    }

    function updateMaxAllowedAmount(uint256 _maxAllowedAmount)
        public
        onlyOwner
    {
        maxAllowedAmount = _maxAllowedAmount;
    }

    function buildDefaultConfig() public view returns (MetaverseNFTConfig memory) {
        return
            MetaverseNFTConfig({
                publicPrice: 0,
                maxTokensPerMint: 5,
                maxTokensPerWallet: 5,
                royaltyFee: 500,
                payoutReceiver: msg.sender,
                shouldLockPayoutReceiver: false,
                shouldStartSale: false,
                shouldUseJsonExtension: false
            });
    }

    function createNFT(
        uint256 _startPrice,
        uint256 _maxSupply,
        uint256 _nReserved,
        uint256 _maxTokensPerMint,
        uint256 _royaltyFee,
        string memory _uri,
        string memory _name,
        string memory _symbol
    ) external hasAccess(msg.sender) {
        require(
            _maxTokensPerMint <= maxPerMintLimit,
            "MetaverseNFTFactory: Overflowed max tokens per mint"
        );
        address clone = Clones.clone(proxyImplementation);

        MetaverseNFT(payable(clone)).initialize(
            _name,
            _symbol,
            _maxSupply,
            _nReserved,
            false,
            _uri,
            buildDefaultConfig()
        );

        MetaverseNFT(payable(clone)).setPrice(_startPrice);
        MetaverseNFT(payable(clone)).setRoyaltyFee(_royaltyFee);
        MetaverseNFT(payable(clone)).updateMaxPerMint(_maxTokensPerMint);
        MetaverseNFT(payable(clone)).updateMaxPerWallet(_maxTokensPerMint);

        MetaverseNFT(payable(clone)).transferOwnership(msg.sender);

        emit NFTCreated(
            clone,
            msg.sender,
            _startPrice,
            _maxSupply,
            _nReserved,
            _name,
            _symbol,
            false,
            false,
            false,
            false
        );
    }

    function createNFTWithSettings(
        uint256 _startPrice,
        uint256 _maxSupply,
        uint256 _nReserved,
        uint256 _maxTokensPerMint,
        uint256 _royaltyFee,
        string memory _uri,
        string memory _name,
        string memory _symbol,
        address payoutReceiver,
        bool shouldUseJsonExtension,
        uint16 miscParams
    ) external hasAccess(msg.sender) {
        require(
            _maxTokensPerMint <= maxPerMintLimit,
            "MetaverseNFTFactory: Overflowed max tokens per mint"
        );
        address clone = Clones.clone(proxyImplementation);

        // params is a bitmask of:

        // bool shouldUseJsonExtension = (miscParams & 0x01) == 0x01;
        // bool startTokenIdAtOne = (miscParams & 0x02) == 0x02;
        // bool shouldStartSale = (miscParams & 0x04) == 0x04;
        // bool shouldLockPayoutReceiver = (miscParams & 0x08) == 0x08;

        MetaverseNFT(payable(clone)).initialize(
            _name,
            _symbol,
            _maxSupply,
            _nReserved,
            miscParams & SHOULD_START_AT_ONE != 0,
            _uri,
            buildDefaultConfig()
            // MetaverseNFTConfig(_startPrice, _maxTokensPerMint, _maxTokensPerMint, _royaltyFee, msg.sender, false, false, false)
        );

        MetaverseNFT(payable(clone)).setPrice(_startPrice);
        MetaverseNFT(payable(clone)).setRoyaltyFee(_royaltyFee);
        MetaverseNFT(payable(clone)).updateMaxPerMint(_maxTokensPerMint);
        MetaverseNFT(payable(clone)).updateMaxPerWallet(_maxTokensPerMint);

        // MetaverseNFT(payable(clone)).setup(
        //     _maxSupply,
        //     _maxTokensPerMint,
        //     _maxTokensPerMint,
        //     _royaltyFee,
        //     payoutReceiver,
        //     miscParams & SHOULD_LOCK_PAYOUT_CHANGE != 0,
        //     miscParams & SHOULD_START_SALE != 0,
        //     shouldUseJsonExtension
        // );

        if (shouldUseJsonExtension) {
            MetaverseNFT(payable(clone)).setPostfixURI(".json");
        }

        if (miscParams & SHOULD_START_SALE != 0) {
            MetaverseNFT(payable(clone)).startSale();
        }

        if (payoutReceiver != address(0)) {
            MetaverseNFT(payable(clone)).setPayoutReceiver(payoutReceiver);
        }

        if (miscParams & SHOULD_LOCK_PAYOUT_CHANGE != 0) {
            MetaverseNFT(payable(clone)).lockPayoutReceiver();
        }

        MetaverseNFT(payable(clone)).transferOwnership(msg.sender);

        emit NFTCreated(
            clone,
            msg.sender,
            _startPrice,
            _maxSupply,
            _nReserved,
            _name,
            _symbol,
            shouldUseJsonExtension,
            miscParams & SHOULD_START_AT_ONE != 0,
            miscParams & SHOULD_START_SALE != 0,
            miscParams & SHOULD_LOCK_PAYOUT_CHANGE != 0
        );
    }

    function createNFTWithoutAccessPass(
        uint256 _startPrice,
        uint256 _maxSupply,
        uint256 _nReserved,
        uint256 _maxTokensPerMint,
        uint256 _royaltyFee,
        string memory _uri,
        string memory _name,
        string memory _symbol,
        address payoutReceiver,
        bool shouldUseJsonExtension,
        uint16 miscParams
    ) external checkTotalAmount(_startPrice * _maxSupply) {
        require(
            _maxTokensPerMint <= maxPerMintLimit,
            "MetaverseNFTFactory: Overflowed max tokens per mint"
        );
        address clone = Clones.clone(proxyImplementation);

        // params is a bitmask of:

        // bool shouldUseJsonExtension = (miscParams & 0x01) == 0x01;
        // bool startTokenIdAtOne = (miscParams & 0x02) == 0x02;
        // bool shouldStartSale = (miscParams & 0x04) == 0x04;
        // bool shouldLockPayoutReceiver = (miscParams & 0x08) == 0x08;

        MetaverseNFT(payable(clone)).initialize(
            _name,
            _symbol,
            _maxSupply,
            _nReserved,
            miscParams & SHOULD_START_AT_ONE != 0,
            _uri,
            buildDefaultConfig()
            // MetaverseNFTConfig(
            //     _startPrice,
            //     _maxTokensPerMint,
            //     _maxTokensPerMint,
            //     _royaltyFee,
            //     payoutReceiver,
            //     miscParams & SHOULD_LOCK_PAYOUT_CHANGE != 0,
            //     miscParams & SHOULD_START_SALE != 0,
            //     shouldUseJsonExtension
            // )
        );

        MetaverseNFT(payable(clone)).setPrice(_startPrice);
        MetaverseNFT(payable(clone)).setRoyaltyFee(_royaltyFee);
        MetaverseNFT(payable(clone)).updateMaxPerMint(_maxTokensPerMint);
        MetaverseNFT(payable(clone)).updateMaxPerWallet(_maxTokensPerMint);

        // MetaverseNFT(payable(clone)).setup(
        //     _startPrice,
        //     _maxTokensPerMint,
        //     _maxTokensPerMint,
        //     _royaltyFee,
        //     payoutReceiver,
        //     miscParams & SHOULD_LOCK_PAYOUT_CHANGE != 0,
        //     miscParams & SHOULD_START_SALE != 0,
        //     shouldUseJsonExtension

        // );

        if (shouldUseJsonExtension) {
            MetaverseNFT(payable(clone)).setPostfixURI(".json");
        }

        if (miscParams & SHOULD_START_SALE != 0) {
            MetaverseNFT(payable(clone)).startSale();
        }

        if (payoutReceiver != address(0)) {
            MetaverseNFT(payable(clone)).setPayoutReceiver(payoutReceiver);
        }

        if (miscParams & SHOULD_LOCK_PAYOUT_CHANGE != 0) {
            MetaverseNFT(payable(clone)).lockPayoutReceiver();
        }

        MetaverseNFT(payable(clone)).transferOwnership(msg.sender);

        emit NFTCreated(
            clone,
            msg.sender,
            _startPrice,
            _maxSupply,
            _nReserved,
            _name,
            _symbol,
            shouldUseJsonExtension,
            miscParams & SHOULD_START_AT_ONE != 0,
            miscParams & SHOULD_START_SALE != 0,
            miscParams & SHOULD_LOCK_PAYOUT_CHANGE != 0
        );
    }
}
