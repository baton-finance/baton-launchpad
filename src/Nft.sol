// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721AUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Caviar, StolenNftFilterOracle} from "caviar/Caviar.sol";
import {Pair} from "caviar/Pair.sol";
import {LpToken} from "caviar/LpToken.sol";
import {BatonFarm} from "baton-contracts/BatonFarm.sol";
import {BatonFactory} from "baton-contracts/BatonFactory.sol";

import {BatonLaunchpad} from "./BatonLaunchpad.sol";

contract Nft is ERC721AUpgradeable, Ownable {
    using SafeTransferLib for address;

    error TooManyCategories();
    error CategoryDoesNotExist();
    error InvalidEthAmount();
    error InsufficientSupply();
    error InvalidMerkleProof();
    error RefundsNotEnabled();
    error MintNotFinished();
    error MintFinished();
    error InsufficientVestedAmount();
    error CategoriesNotSortedByPrice();
    error InsufficientEthRaisedForLockedLp();
    error LockedLpNotEnabled();
    error InsufficientLpAmount();
    error LpStillBeingLocked();
    error InvalidNftAmount();
    error YieldFarmNotEnabled();
    error InsufficientYieldFarmAmount();
    error YieldFarmStillBeingSeeded();
    error MigrationNotInitiated();
    error MigrationTargetNotMatched();

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
    BatonFactory public immutable batonFactory;

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
    BatonFarm public yieldFarm;
    uint32 public seededYieldFarmSupply;
    address public lockedLpMigrationTarget;

    constructor(address caviar_, address batonLaunchpad_, address batonFactory_) {
        caviar = Caviar(caviar_);
        batonLaunchpad = BatonLaunchpad(payable(batonLaunchpad_));
        batonFactory = BatonFactory(payable(batonFactory_));
    }

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address owner,
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

        // initialize the owner
        _initializeOwner(owner);

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

        // check that enough eth was sent
        uint256 feeRate = batonLaunchpad.feeRate(); // <-- 🛠️ Early interaction (safe)
        uint256 fee = category.price * amount * feeRate / 1e18;
        if (msg.value != category.price * amount + fee) revert InvalidEthAmount();

        // check that there is enough supply
        minted[categoryIndex] += amount; // <-- 👷 Early effect (safe)
        if (minted[categoryIndex] > category.supply || totalSupply() + amount > maxMintSupply) {
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

        if (refunds) {
            // track the total minted and available refunds for each account if refunds are enabled
            _accounts[msg.sender].totalMinted += amount;
            _accounts[msg.sender].availableRefund += category.price * amount;
        }

        // mint the tokens
        _safeMint(msg.sender, amount);

        if (totalSupply() == maxMintSupply) {
            // set the mint end timestamp if mint is complete
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

        // check that the mint has not finished
        if (mintEndTimestamp != 0) revert MintFinished();

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
        uint256[] memory tokenIds = new uint256[](amount); // todo: put the correct token ids here so that reservoir can track them
        uint256 baseTokenAmount = _lockLpParams.price * amount;
        pair.nftAdd{value: baseTokenAmount}(
            baseTokenAmount, tokenIds, 0, 0, type(uint256).max, 0, new bytes32[][](0), messages
        );
    }

    function seedYieldFarm(uint32 amount, StolenNftFilterOracle.Message[] calldata messages) public {
        // ✅ Checks ✅

        // check that yield farm is enabled
        if (_yieldFarmParams.amount == 0) revert YieldFarmNotEnabled();

        // check that the mint has ended
        if (mintEndTimestamp == 0) revert MintNotFinished();

        // check that locked lp has ended (if locked lp is disabled then 0 == 0 here)
        if (lockedLpSupply != _lockLpParams.amount) revert LpStillBeingLocked();

        // check that there are enough nfts available to seed the farm
        seededYieldFarmSupply += amount; // <-- 👷 Early effect (safe)
        if (seededYieldFarmSupply > _yieldFarmParams.amount) revert InsufficientYieldFarmAmount();

        // 🛠️ Interactions 🛠️

        // if the caviar pair does not exist then create it
        Pair pair = Pair(caviar.pairs(address(this), address(0), bytes32(0)));
        if (address(pair) == address(0)) {
            pair = caviar.create(address(this), address(0), bytes32(0));
        }

        // mint the nfts to caviar
        _mint(address(pair), amount); // <-- 👷 Late effect (safe)

        // wrap the nfts and get fractional tokens
        uint256[] memory tokenIds = new uint256[](amount);
        bytes32[][] memory proofs = new bytes32[][](0);
        uint256 rewardTokenAmount = pair.wrap(tokenIds, proofs, messages);

        // if the yield farm does not exist then create it
        if (address(yieldFarm) == address(0)) {
            // approve the baton factory to transfer the tokens
            pair.approve(address(batonFactory), type(uint256).max);

            // create the yield farm and seed with some rewards
            yieldFarm = BatonFarm(
                payable(
                    batonFactory.createFarmFromExistingPairERC20({
                        _owner: address(this),
                        _rewardsToken: address(pair),
                        _rewardAmount: rewardTokenAmount,
                        _pairAddress: address(pair),
                        _rewardsDuration: _yieldFarmParams.duration
                    })
                )
            );

            // approve the yield farm to transfer the tokens
            pair.approve(address(yieldFarm), type(uint256).max);
        } else {
            // add the tokens to the yield farm
            yieldFarm.notifyRewardAmount(rewardTokenAmount);
        }
    }

    function withdraw() public onlyOwner {
        // ✅ Checks ✅

        // check that the mint has ended
        if (mintEndTimestamp == 0) revert MintNotFinished();

        // check that locked lp has been fully locked (if locked lp is disabled then 0 == 0 here)
        if (lockedLpSupply != _lockLpParams.amount) revert LpStillBeingLocked();

        // check if yield farm has finished seeding (if yield farm is disabled then 0 == 0 here)
        if (seededYieldFarmSupply != _yieldFarmParams.amount) revert YieldFarmStillBeingSeeded();

        // send the remaining eth in the contract to the owner
        owner().safeTransferETH(address(this).balance);
    }

    function initiateLockedLpMigration(address target) public onlyOwner {
        // set the destination address for the lp tokens
        lockedLpMigrationTarget = target;
    }

    function migrateLockedLp(address target) public {
        // ✅ Checks ✅

        // check that the caller is the baton owner
        if (msg.sender != batonLaunchpad.owner()) revert Unauthorized();

        // check that the migration target has been set by the nft owner
        if (lockedLpMigrationTarget == address(0)) revert MigrationNotInitiated();

        // check that the migration target matches the target set by the nft owner (this check prevents frontrunning)
        if (target != lockedLpMigrationTarget) revert MigrationTargetNotMatched();

        // 🛠️ Interactions 🛠️

        // transfer the lp tokens to the migration target
        LpToken lpToken = Pair(caviar.pairs(address(this), address(0), bytes32(0))).lpToken();
        lpToken.transfer(lockedLpMigrationTarget, lpToken.balanceOf(address(this)));
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

    function yieldFarmParams() public view returns (YieldFarmParams memory) {
        return _yieldFarmParams;
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
