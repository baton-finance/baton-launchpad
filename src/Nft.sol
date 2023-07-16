// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721AUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {Pair} from "caviar/Pair.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

import {BatonLaunchpad} from "./BatonLaunchpad.sol";

contract Nft is ERC721AUpgradeable {
    using SafeTransferLib for address;

    error TooManyCategories();
    error CategoryDoesNotExist();
    error InvalidEthAmount();
    error InsufficientSupply();
    error InvalidMerkleProof();
    error RefundsNotEnabled();
    error Unauthorized();
    error MintNotFinished();
    error InsufficientVestedAmount();
    error CategoriesNotSortedByPrice();
    error InsufficientEthRaisedForLockedLp();
    error LockedLpNotEnabled();
    error InsufficientLpAmount();
    error LpStillBeingLocked();
    error InvalidNftAmount();
    error YieldFarmNotEnabled();

    struct Category {
        uint128 price;
        uint128 supply;
        bytes32 merkleRoot;
    }

    struct Account {
        uint128 totalMinted;
        uint128 availableRefund;
    }

    struct VestingParams {
        address receiver;
        uint64 duration;
        uint32 amount;
    }

    struct LockLpParams {
        uint32 amount;
        uint128 price;
    }

    struct YieldFarmParams {
        uint32 amount;
        uint64 duration;
    }

    // immutables
    Caviar public immutable caviar;
    BatonLaunchpad public immutable batonLaunchpad;

    // feature parameters
    Category[] internal _categories;
    VestingParams internal _vestingParams;
    LockLpParams internal _lockLpParams;
    YieldFarmParams internal _yieldFarmParams;
    bool public refunds;

    mapping(uint8 categoryIndex => uint256) public minted;
    mapping(uint256 tokenId => uint256) public pricePaid;
    mapping(address => Account) public _accounts;
    uint64 public mintEndTimestamp;
    uint32 public totalVestClaimed;
    uint32 public maxMintSupply;
    uint32 public lockedLpSupply;

    constructor(address caviar_, address batonLaunchpad_) {
        caviar = Caviar(caviar_);
        batonLaunchpad = BatonLaunchpad(payable(batonLaunchpad_));
    }

    function initialize(
        string calldata name_,
        string calldata symbol_,
        Category[] calldata categories_,
        uint32 maxMintSupply_,
        bool refunds_,
        VestingParams calldata vestingParams_,
        LockLpParams calldata lockLpParams_,
        YieldFarmParams calldata yieldFarmParams_
    ) public initializerERC721A {
        // check that there is less than 256 categories
        if (categories_.length > 256) revert TooManyCategories();

        // check that enough eth will be raised for the locked lp
        if (lockLpParams_.amount * lockLpParams_.price > minEthRaised(categories_, maxMintSupply_)) {
            revert InsufficientEthRaisedForLockedLp();
        }

        // initialize the ERC721AUpgradeable
        __ERC721A_init(name_, symbol_);

        // push all categories
        for (uint256 i = 0; i < categories_.length; i++) {
            _categories.push(categories_[i]);
        }

        // set the max mint supply
        maxMintSupply = maxMintSupply_;

        // set the refunds flag
        refunds = refunds_;

        // set the vesting params
        _vestingParams = vestingParams_;

        // set the lock lp params
        _lockLpParams = lockLpParams_;

        // set the yield farm params
        _yieldFarmParams = yieldFarmParams_;
    }

    function mint(uint64 amount, uint8 categoryIndex, bytes32[] calldata proof) public payable {
        // ✅ Checks ✅

        Category memory category = _categories[categoryIndex];

        // check that input amount of nfts to mint is not zero
        if (amount == 0) revert InvalidNftAmount();

        uint256 feeRate = batonLaunchpad.feeRate(); // <-- 🛠️ Early interaction (safe)
        uint256 fee = category.price * amount * feeRate / 1e18;

        // check that enough eth was sent
        if (msg.value != category.price * amount + fee) revert InvalidEthAmount();

        // check that there is enough supply
        if (minted[categoryIndex] + amount > category.supply || totalSupply() + amount > maxMintSupply) {
            revert InsufficientSupply();
        }

        // if the merkle root is not zero then verify that the caller is whitelisted
        if (
            category.merkleRoot != bytes32(0)
                && !MerkleProofLib.verifyCalldata(
                    proof, category.merkleRoot, keccak256(bytes.concat(keccak256(abi.encode(msg.sender))))
                )
        ) {
            revert InvalidMerkleProof();
        }

        // 👷 Effects 👷

        // update the minted amount
        minted[categoryIndex] += amount;

        if (refunds) {
            // update the account info
            _accounts[msg.sender].totalMinted += amount;
            _accounts[msg.sender].availableRefund += category.price * amount;
        }

        // mint the tokens
        _safeMint(msg.sender, amount);

        if ((_vestingParams.receiver != address(0) || _lockLpParams.amount > 0) && totalSupply() == maxMintSupply) {
            // set the mint end timestamp if vesting or locked lp is enabled and mint is complete
            mintEndTimestamp = uint64(block.timestamp);
        }

        // 🛠️ Interactions 🛠️

        if (fee > 0) {
            // transfer the fee
            address(batonLaunchpad).safeTransferETH(fee);
        }
    }

    function refund(uint256[] calldata tokenIds) public {
        // ✅ Checks ✅

        // check that refunds are enabled
        if (!refunds) revert RefundsNotEnabled();

        // 👷 Effects 👷

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // burn the token and check the caller owns them
            _burn(tokenIds[i], true);
        }

        // get the total refund amount
        uint256 totalRefundAmount =
            tokenIds.length * _accounts[msg.sender].availableRefund / _accounts[msg.sender].totalMinted;

        // update the account info
        _accounts[msg.sender].totalMinted -= uint128(tokenIds.length);
        _accounts[msg.sender].availableRefund -= uint128(totalRefundAmount);

        // 🛠️ Interactions 🛠️

        // send the refund
        msg.sender.safeTransferETH(totalRefundAmount);
    }

    function vest(uint256 amount) public {
        // ✅ Checks ✅

        // check the caller is the vesting receiver
        if (msg.sender != _vestingParams.receiver) revert Unauthorized();

        // check that the mint has finished
        if (mintEndTimestamp == 0) revert MintNotFinished();

        // check that there is enough available
        uint256 available = vested() - totalVestClaimed;
        if (amount > available) revert InsufficientVestedAmount();

        // 👷 Effects 👷

        // update the total vest claimed
        totalVestClaimed += uint32(amount);

        // mint the nfts
        _safeMint(msg.sender, amount);
    }

    function lockLp(uint32 amount, StolenNftFilterOracle.Message[] calldata messages) public {
        // ✅ Checks ✅

        // check that the mint has ended
        if (mintEndTimestamp == 0) revert MintNotFinished();

        // check that locked lp is enabled
        if (_lockLpParams.amount == 0) revert LockedLpNotEnabled();

        // update the locked lp supply
        lockedLpSupply += amount; // <-- 👷 Early effect (safe)

        // check that there is enough available
        if (lockedLpSupply > _lockLpParams.amount) revert InsufficientLpAmount();

        // 👷 Effects 👷

        uint256[] memory tokenIds = new uint256[](amount);
        uint256 nextTokenId = _nextTokenId();
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = nextTokenId + i;
        }

        // 🛠️ Interactions 🛠️

        // if the caviar pair does not exist then create it
        Pair pair = Pair(caviar.pairs(address(this), address(0), bytes32(0)));
        if (address(pair) == address(0)) {
            pair = caviar.create(address(this), address(0), bytes32(0));
        }

        // mint the tokens directly to the pair. this is done to take advantage of ERC721A's
        // amortization of the gas cost of minting. we save a lot of gas by doing this.
        _mint(address(pair), amount); // <-- 👷 Late effect (safe)

        // approve the pair to transfer the NFTs
        this.setApprovalForAll(address(pair), true);

        // deposit liquidity into the pair
        // we can ignore the min lp token and price bounds as we are the only ones that can deposit into the pair due
        // to the transferFrom lock which prevents anyone transferring NFTs to the pair until the liquidity is locked.
        uint256 baseTokenAmount = _lockLpParams.price * tokenIds.length;
        pair.nftAdd{value: baseTokenAmount}(
            baseTokenAmount, tokenIds, 0, 0, type(uint256).max, 0, new bytes32[][](0), messages
        );
    }

    function seedYieldFarm(uint256 amount, StolenNftFilterOracle.Message[] calldata messages) public {
        // ✅ Checks ✅

        // check that the mint has ended
        if (mintEndTimestamp == 0) revert MintNotFinished();

        // check that locked lp has ended (if locked lp is disabled then 0 == 0 here)
        if (lockedLpSupply != _lockLpParams.amount) revert LpStillBeingLocked();

        // check that yield farm is enabled
        if (_yieldFarmParams.amount == 0) revert YieldFarmNotEnabled();

        // 👷 Effects 👷

        uint256[] memory tokenIds = new uint256[](amount);
        uint256 nextTokenId = _nextTokenId();
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = nextTokenId + i;
        }

        // 🛠️ Interactions 🛠️

        // if the caviar pair does not exist then create it
        Pair pair = Pair(caviar.pairs(address(this), address(0), bytes32(0)));
        if (address(pair) == address(0)) {
            pair = caviar.create(address(this), address(0), bytes32(0));
        }

        // mint the nfts to caviar
        _mint(address(pair), amount);

        // wrap the nfts
        bytes32[][] memory proofs = new bytes32[][](0);
        pair.wrap(tokenIds, proofs, messages);

        // if the yield farm doesn't exist then create the yield farm

        // distribute the rewards to the yield farm via notifyRewardAmount
    }

    function vested() public view returns (uint256) {
        if (mintEndTimestamp == 0) return 0;

        uint256 vestingRate = uint256(_vestingParams.amount) * 1e18 / uint256(_vestingParams.duration);

        return FixedPointMathLib.mulDivUp(
            vestingRate,
            min(block.timestamp, mintEndTimestamp + _vestingParams.duration) - uint256(mintEndTimestamp),
            1e18
        );
    }

    function categories(uint8 category) public view returns (Category memory) {
        return _categories[category];
    }

    function accounts(address account) public view returns (Account memory) {
        return _accounts[account];
    }

    function vestingParams() public view returns (VestingParams memory) {
        return _vestingParams;
    }

    function lockLpParams() public view returns (LockLpParams memory) {
        return _lockLpParams;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function minEthRaised(Category[] calldata categories, uint256 availableMintSupply) public pure returns (uint256) {
        uint256 minEth = 0;

        for (uint256 i = 0; i < categories.length; i++) {
            // check that the categories are sorted by price
            if (i != 0 && categories[i - 1].price > categories[i].price) revert CategoriesNotSortedByPrice();

            // add to the total min eth raised
            minEth += categories[i].price * min(categories[i].supply, availableMintSupply);
            availableMintSupply -= min(categories[i].supply, availableMintSupply);

            // break if there is no more available mint supply
            if (availableMintSupply == 0) break;
        }

        return minEth;
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable override {
        // Skip doing any state changes if the caviar pair attempts to transfer tokens from this contract to the pair.
        // We don't need to do the transfer because in the seedYieldFarm and lockLp functions we mint the NFTs directly
        // to the caviar pair already.
        if (from == address(this)) {
            address pair = caviar.pairs(address(this), address(0), bytes32(0));

            if (to == pair && msg.sender == pair) {
                return;
            }
        }

        // disable all transfers to the caviar pair until the lp has finished locking.
        // if lp locking is not enabled then this will always be false (0 < 0 == false).
        if (lockedLpSupply < _lockLpParams.amount && from != address(this)) {
            address pair = caviar.pairs(address(this), address(0), bytes32(0));

            // check that the transfer is not to the caviar pair
            if (to == pair || from == pair) revert LpStillBeingLocked();
        }

        super.transferFrom(from, to, tokenId);
    }
}
