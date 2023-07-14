// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721AUpgradeable} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

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

    // feature parameters
    Category[] internal _categories;
    VestingParams public _vestingParams;
    bool public refunds;

    mapping(uint8 categoryIndex => uint256) public minted;
    mapping(uint256 tokenId => uint256) public pricePaid;
    mapping(address => Account) public _accounts;
    uint64 public mintEndTimestamp;
    uint32 public totalVestClaimed;
    uint32 public maxMintSupply;

    function initialize(
        string calldata name_,
        string calldata symbol_,
        Category[] calldata categories_,
        bool refunds_,
        VestingParams calldata vestingParams_
    ) public initializerERC721A {
        // check that there is less than 256 categories
        if (categories_.length > 256) revert TooManyCategories();

        // initialize the ERC721AUpgradeable
        __ERC721A_init(name_, symbol_);

        // push all categories
        for (uint256 i = 0; i < categories_.length; i++) {
            _categories.push(categories_[i]);

            // update the max mint supply
            maxMintSupply += uint32(categories_[i].supply);
        }

        // set the refunds flag
        refunds = refunds_;

        // set the vesting params
        _vestingParams = vestingParams_;
    }

    function mint(uint64 amount, uint8 categoryIndex, bytes32[] calldata proof) public payable {
        // ✅ Checks ✅

        Category memory category = _categories[categoryIndex];

        // check that the price is correct
        if (msg.value != category.price * amount) revert InvalidEthAmount();

        // check that there is enough supply
        if (minted[categoryIndex] + amount > category.supply) revert InsufficientSupply();

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

        if (_vestingParams.receiver != address(0) && totalSupply() + amount == maxMintSupply) {
            // set the mint end timestamp if vesting is enabled and mint is complete
            mintEndTimestamp = uint64(block.timestamp);
        }

        // mint the tokens
        _safeMint(msg.sender, amount);
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

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
