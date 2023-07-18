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

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Errors

    error TooManyCategories();
    error TooFewCategories();
    error CategoriesNotSortedByPrice();
    error InvalidVestingParams();
    error InvalidLockLpParams();
    error InvalidYieldFarmParams();
    error InvalidRefundParams();
    error InvalidEthAmount();
    error InsufficientSupply();
    error InvalidMerkleProof();
    error RefundsNotEnabled();
    error MintComplete();
    error MintNotComplete();
    error MintExpired();
    error MintNotExpired();
    error InsufficientVestedAmount();
    error VestingNotStarted();
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

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Events

    event Mint(address indexed account, uint256 indexed amount, uint256 indexed price);
    event Refund(address indexed account, uint256 indexed nftAmount, uint256 indexed ethAmount);
    event Vest(uint256 indexed amount);
    event LockLp(address indexed account, uint256 indexed amount);
    event SeedYieldFarm(address indexed account, uint256 indexed amount);
    event Withdraw(uint256 indexed ethAmount);
    event InitiateLockedLpMigration(address indexed target);
    event MigrateLockedLp(address indexed target, uint256 indexed lpTokenAmount);

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Structs

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

    struct RefundParams {
        uint64 mintEndTimestamp;
    }

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Immutables

    Caviar public immutable caviar;
    BatonLaunchpad public immutable batonLaunchpad;
    BatonFactory public immutable batonFactory;

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Feature parameters

    Category[] internal _categories;
    VestingParams internal _vestingParams;
    LockLpParams internal _lockLpParams;
    YieldFarmParams internal _yieldFarmParams;
    RefundParams internal _refundParams;

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// State variables

    mapping(uint8 categoryIndex => uint256) public minted;
    mapping(address => Account) internal _accounts;
    uint64 public mintCompleteTimestamp;
    uint32 public totalVestClaimed;
    uint32 public maxMintSupply;
    uint32 public lockedLpSupply;
    BatonFarm public yieldFarm;
    uint32 public seededYieldFarmSupply;
    address public lockedLpMigrationTarget;

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Initializers

    constructor(address caviar_, address batonLaunchpad_, address batonFactory_) {
        caviar = Caviar(caviar_);
        batonLaunchpad = BatonLaunchpad(payable(batonLaunchpad_));
        batonFactory = BatonFactory(payable(batonFactory_));
    }

    /**
     * @notice Initialize the NFT contract.
     * @param name_ The name of the NFT.
     * @param symbol_ The symbol of the NFT.
     * @param categories_ The categories of the NFT (you must specify at least one category).
     * @param maxMintSupply_ The max mint supply of the NFT.
     * @param refundParams_ The refund params (optional).
     * @param vestingParams_ The vesting params (optional).
     * @param lockLpParams_ The lock LP params (optional).
     * @param yieldFarmParams_ The yield farm params of the NFT (optional).
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address owner_,
        Category[] memory categories_,
        uint32 maxMintSupply_,
        RefundParams memory refundParams_,
        VestingParams memory vestingParams_,
        LockLpParams memory lockLpParams_,
        YieldFarmParams memory yieldFarmParams_
    ) public initializerERC721A {
        // ✅ Checks ✅

        // check that there is less than 256 categories
        if (categories_.length > 256) revert TooManyCategories();

        // check that there is at least one category
        if (categories_.length == 0) revert TooFewCategories();

        // check that enough eth will be raised from the mint for the locked lp. for example, if there are 100 nfts reserved
        // for the locked lp at a price of 0.1 eth, then we need to raise at least 10 eth for the locked lp to work.
        if (lockLpParams_.amount * lockLpParams_.price > minEthRaised(categories_, maxMintSupply_)) {
            revert InsufficientEthRaisedForLockedLp();
        }

        // check that if the vesting params are set the amount and receiver must not be 0
        if (
            (vestingParams_.receiver != address(0) && vestingParams_.amount == 0)
                || (vestingParams_.receiver == address(0) && vestingParams_.amount != 0)
        ) revert InvalidVestingParams();

        // check that if the lock lp params are set then the amount and price must not be 0
        if (
            (lockLpParams_.amount != 0 && lockLpParams_.price == 0)
                || (lockLpParams_.amount == 0 && lockLpParams_.price != 0)
        ) revert InvalidLockLpParams();

        // check that if the yield farm params are set then the amount and duration must not be 0
        if (
            (yieldFarmParams_.duration != 0 && yieldFarmParams_.amount == 0)
                || (yieldFarmParams_.duration == 0 && yieldFarmParams_.amount != 0)
        ) revert InvalidYieldFarmParams();

        // check that if the refund params are set then the mint end timestamp must be greater than the current time
        if (refundParams_.mintEndTimestamp != 0 && refundParams_.mintEndTimestamp < block.timestamp) {
            revert InvalidRefundParams();
        }

        // 👷 Effects 👷

        // initialize the ERC721AUpgradeable
        __ERC721A_init(name_, symbol_);

        // initialize the owner
        _initializeOwner(owner_);

        // push all categories
        for (uint256 i = 0; i < categories_.length; i++) {
            _categories.push(categories_[i]);
        }

        // set the max mint supply
        maxMintSupply = maxMintSupply_;

        // set the refunds flag
        _refundParams = refundParams_;

        // set the vesting params
        _vestingParams = vestingParams_;

        // set the lock lp params
        _lockLpParams = lockLpParams_;

        // set the yield farm params
        _yieldFarmParams = yieldFarmParams_;
    }

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Core logic functions

    /**
     * @notice Mints an amount of NFTs to the caller from a specific category. The caller must pay
     * the price that is specified in the category and if there is a whitelist associated with the
     * category then they must also submit a merkle proof showing that they are in the whitelist.
     * @param amount The amount of NFTs to mint
     * @param categoryIndex The index of the category to mint from
     * @param proof The merkle proof (if not required then set to be an empty array)
     */
    function mint(uint64 amount, uint8 categoryIndex, bytes32[] calldata proof) public payable {
        // ✅ Checks ✅

        Category memory category = _categories[categoryIndex];

        // check that input amount of nfts to mint is not zero
        if (amount == 0) revert InvalidNftAmount();

        // if refunds are enabled, check that the mint has not expired
        if (_refundParams.mintEndTimestamp != 0 && block.timestamp > _refundParams.mintEndTimestamp) {
            revert MintExpired();
        }

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
            // todo: is it necessary to do a double hash of the caller here?
            && !MerkleProofLib.verifyCalldata(
                proof, category.merkleRoot, keccak256(bytes.concat(keccak256(abi.encode(msg.sender))))
            )
        ) {
            revert InvalidMerkleProof();
        }

        // 👷 Effects 👷

        if (_refundParams.mintEndTimestamp != 0) {
            // track the total minted and available refunds for each account if refunds are enabled
            _accounts[msg.sender].totalMinted += amount;
            _accounts[msg.sender].availableRefund += category.price * amount;
        }

        // mint the tokens to the caller
        _mint(msg.sender, amount);

        if (totalSupply() == maxMintSupply) {
            // set the mint completion timestamp
            mintCompleteTimestamp = uint64(block.timestamp);
        }

        // 🛠️ Interactions 🛠️

        if (fee > 0) {
            // transfer the protocol fee
            address(batonLaunchpad).safeTransferETH(fee);
        }

        emit Mint(msg.sender, amount, category.price);
    }

    // todo: add some invariant tests e.g. should always have enough money to lock the lp

    /**
     * @notice Refunds eth to the caller for a specific set of token ids. The refund that they are entitled to is
     * based on how much they spent on minting NFTs. For example, if they spent a total of 5 eth on 5 NFTs then
     * they are entitled to a refund of 1 ETH per NFT burned. Refunds can only be claimed while the mint is still
     * live. This feature is optional and only works if the creator of the contract enables it.
     * @param tokenIds The token ids to refund
     */
    function refund(uint256[] calldata tokenIds) public {
        // ✅ Checks ✅

        // check that refunds are enabled
        if (_refundParams.mintEndTimestamp == 0) revert RefundsNotEnabled();

        // check that the mint failed to complete
        if (mintCompleteTimestamp != 0) revert MintComplete();

        // check that the mint has expired
        if (block.timestamp <= _refundParams.mintEndTimestamp) revert MintNotExpired();

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

        emit Refund(msg.sender, tokenIds.length, totalRefundAmount);
    }

    /**
     * @notice Mints NFTs to the vesting receiver. The amount of NFTs that can be minted is based on the vesting rate
     * and how much time has passed since the last time this function was called.
     * @param amount The amount of NFTs to mint
     */
    function vest(uint256 amount) public {
        // ✅ Checks ✅

        // check the caller is the vesting receiver
        if (msg.sender != _vestingParams.receiver) revert Unauthorized();

        // if the mint end timestamp is set then check that the mint has expired, otherwise check that the mint
        // has completed (fully minted out).
        if (
            _refundParams.mintEndTimestamp != 0
                ? block.timestamp < _refundParams.mintEndTimestamp
                : mintCompleteTimestamp == 0
        ) {
            revert VestingNotStarted();
        }

        // check that there is enough available
        uint256 available = vested() - totalVestClaimed;
        if (amount > available) revert InsufficientVestedAmount();

        // 👷 Effects 👷

        // update the total vest claimed
        totalVestClaimed += uint32(amount);

        // mint the nfts
        _mint(msg.sender, amount);

        emit Vest(amount);
    }

    /**
     * @notice Mints an amount of NFTs and then deposits them as liquidity into a Caviar pool; using
     * ETH proceeds from the mint as the other side. The price of the NFTs is based on the price set
     * in the lockLpParams variable. This function can be repeatedly called until all of the liquidity
     * has been locked (based on the lockLpParams variable).
     * @param amount The amount of NFTs to mint
     * @param messages The messages from Reservoir proving that the newly minted NFTs are not stolen
     */
    function lockLp(uint32 amount, StolenNftFilterOracle.Message[] calldata messages) public {
        // ✅ Checks ✅

        // check that the mint has completed (fully minted out)
        if (mintCompleteTimestamp == 0) revert MintNotComplete();

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

        // calculate the token ids for each of the newly minted nfts
        uint256[] memory tokenIds = new uint256[](amount);
        uint256 nextTokenId = _nextTokenId();
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = nextTokenId + i;
        }

        // mint the tokens directly to the pair. this is done to take advantage of ERC721A's
        // amortization of the gas cost of minting. we save a lot of gas by doing this.
        _mint(address(pair), amount); // <-- 👷 Late effect (safe)

        // deposit liquidity into the pair
        // we can ignore the min lp token and price bounds as we are the only ones that can deposit into the pair due
        // to the transferFrom lock which prevents anyone transferring NFTs to the pair until the liquidity is locked
        // -- meaning that frontrunning is not an issue.
        uint256 baseTokenAmount = _lockLpParams.price * amount;
        pair.nftAdd{value: baseTokenAmount}(
            baseTokenAmount, tokenIds, 0, 0, type(uint256).max, 0, new bytes32[][](0), messages
        );

        emit LockLp(msg.sender, amount);
    }

    /**
     * @notice Seeds the yield farm on Baton with an amount of NFTs. If this is the first time that the function is
     * called then a new yield farm will be deployed and initialized. Otherwise, this function can be repeatedly
     * called until all of the NFTs have been seeded (based on the yieldFarmParams variable). If locked LP is
     * enabled then all of liquidity has to be locked before this function can be called.
     * @param amount The amount of NFTs to seed
     * @param messages The messages from Reservoir proving that the newly minted NFTs are not stolen
     */
    function seedYieldFarm(uint32 amount, StolenNftFilterOracle.Message[] calldata messages) public {
        // ✅ Checks ✅

        // check that yield farm is enabled
        if (_yieldFarmParams.amount == 0) revert YieldFarmNotEnabled();

        // check that the mint has completed
        if (mintCompleteTimestamp == 0) revert MintNotComplete();

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

        // calculate the token ids for each of the newly minted nfts
        uint256[] memory tokenIds = new uint256[](amount);
        uint256 nextTokenId = _nextTokenId();
        for (uint256 i = 0; i < amount; i++) {
            tokenIds[i] = nextTokenId + i;
        }

        // mint the nfts to caviar
        _mint(address(pair), amount); // <-- 👷 Late effect (safe)

        // wrap the nfts and get fractional tokens
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

        emit SeedYieldFarm(msg.sender, amount);
    }

    /**
     * @notice Withdraws ETH from the contract to the owner. This function can only be called after the mint has completed,
     * the liquidity has been locked (if enabled), and the yield farm seeded (if enabled).
     */
    function withdraw() public onlyOwner {
        // ✅ Checks ✅

        // check that the mint has completed
        if (mintCompleteTimestamp == 0) revert MintNotComplete();

        // check that locked lp has been fully locked (if locked lp is disabled then 0 == 0 here)
        if (lockedLpSupply != _lockLpParams.amount) revert LpStillBeingLocked();

        // check if yield farm has finished seeding (if yield farm is disabled then 0 == 0 here)
        if (seededYieldFarmSupply != _yieldFarmParams.amount) revert YieldFarmStillBeingSeeded();

        // send the remaining eth in the contract to the owner
        uint256 ethAmount = address(this).balance;
        owner().safeTransferETH(ethAmount);

        emit Withdraw(ethAmount);
    }

    /**
     * @notice Initiates a migration of the locked lp tokens to a new target address. This function is the first of two required
     * functions that need to be called before a migration can be finalized. It can only be called by the owner of this contract.
     * The second function (migrateLockedLp) can only be called by the Baton admin. This provides an escape hatch to allow for
     * migration of liquidity to newer versions of NFT AMMs.
     * @param target The address that the locked lp tokens will be migrated to
     */
    function initiateLockedLpMigration(address target) public onlyOwner {
        // set the destination address for the lp tokens
        lockedLpMigrationTarget = target;

        emit InitiateLockedLpMigration(target);
    }

    /**
     * @notice Finalizes a migration of the locked lp tokens to a new target address. This function is the second of two required
     * functions that need to be called before a migration can be finalized. It can only be called by the Baton admin. The first
     * function can only be called by the owner of this contract.
     * @param target The address that the locked lp tokens will be migrated to (must match the address set in initiateLockedLpMigration)
     */
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
        uint256 lpTokenAmount = lpToken.balanceOf(address(this));
        lpToken.transfer(lockedLpMigrationTarget, lpTokenAmount);

        emit MigrateLockedLp(target, lpTokenAmount);
    }

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Getters

    /**
     * @return The total amount of vested tokens
     */
    function vested() public view returns (uint256) {
        // if the mint end timestamp has been set then start vesting at the mint end timestamp, otherwise
        // start vesting at the mint complete timestamp (when all available nfts have been minted)
        uint256 vestingStartTimestamp =
            _refundParams.mintEndTimestamp != 0 ? _refundParams.mintEndTimestamp : mintCompleteTimestamp;
        if (vestingStartTimestamp == 0 || block.timestamp < vestingStartTimestamp) return 0;

        // if no vesting duration is set then return the full amount
        if (_vestingParams.duration == 0) return uint256(_vestingParams.amount);

        uint256 vestingRate = uint256(_vestingParams.amount) * 1e18 / uint256(_vestingParams.duration);

        return min(
            uint256(_vestingParams.amount),
            FixedPointMathLib.mulDivUp(
                vestingRate,
                min(block.timestamp, vestingStartTimestamp + _vestingParams.duration) - uint256(vestingStartTimestamp),
                1e18
            )
        );
    }

    /**
     * @notice Calculates the minimum amount of ETH that will be raised if the mint completes. For example, consider
     * the following configuration:
     *  - availableMintSupply = 100
     *  - category 1 = supply 150, price 2 ether
     *  - category 2 = supply 50, price 6 ether
     * then the minimum that can be raised if the mint completes is 200 ether = 2 ether (category 1 price) * 100 (available mint supply)
     * @param categories The categories to calculate the minimum eth raised for
     * @param availableMintSupply The amount of tokens that are still available to be minted
     * @return The minimum amount of ETH that will be raised if the mint completes
     */
    function minEthRaised(Category[] memory categories, uint256 availableMintSupply) public pure returns (uint256) {
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

    function refundParams() public view returns (RefundParams memory) {
        return _refundParams;
    }

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Helpers

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// ░░░░░░░░░░░░░░░░░░░░░░░░░
    /// Overrides

    /**
     * @notice Transfers tokens from one address to another
     * @dev This function prevents any transfers to the caviar pair until the lp has finished locking. It also returns
     * early if the caviar pair attempts to transfer tokens from this contract to the pair. This should only be the case
     * during the lp locking process (pair.nftAdd) or yield farming process (pair.wrap). In each of these cases, we
     * mint the tokens directly to the caviar pair so we don't need to do the transfer. This allows us to take advantage
     * of the amortized gas savings that are applied when minting tokens from the ERC721A library.
     * @param from The address to transfer tokens from
     * @param to The address to transfer tokens to
     * @param tokenId The id of the token to transfer
     */
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
