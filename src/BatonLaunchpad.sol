// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {LibClone} from "solady/utils/LibClone.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Nft} from "./Nft.sol";

contract BatonLaunchpad is Ownable {
    using LibClone for address;
    using SafeTransferLib for address;

    error FeeRateTooLarge();

    event Create(address indexed nft);
    event SetNftImplementation(address indexed nftImplementation);
    event SetFeeRate(uint256 feeRate);

    /**
     * @dev Use a struct to avoid "stack too deep" error.
     * @param name The name of the NFT.
     * @param symbol The symbol of the NFT.
     * @param categories The categories of the NFT.
     * @param maxMintSupply The max mint supply of the NFT.
     * @param refundParams_ The refund params.
     * @param vestingParams The vesting params of the NFT.
     * @param lockLpParams The lock LP params of the NFT.
     * @param yieldFarmParams The yield farm params of the NFT.
     * @return nft The address of the newly created NFT contract.
     */
    struct CreateParams {
        string name;
        string symbol;
        Nft.Category[] categories;
        uint32 maxMintSupply;
        uint96 royaltyRate;
        Nft.RefundParams refundParams;
        Nft.VestingParams vestingParams;
        Nft.LockLpParams lockLpParams;
        Nft.YieldFarmParams yieldFarmParams;
    }

    address public nftImplementation;
    uint256 public feeRate;

    constructor(uint256 _feeRate) {
        _initializeOwner(msg.sender);
        setFeeRate(_feeRate);
    }

    receive() external payable {}

    /**
     * @notice Creates a new NFT contract.
     * @param createParams The parameters used to create the NFT.
     * @param salt The salt used when cloning the NFT via create2 (must be unique).
     * @return nft The address of the newly created NFT contract.
     */
    function create(CreateParams memory createParams, bytes32 salt) external returns (Nft nft) {
        salt = keccak256(abi.encodePacked(salt, msg.sender));
        nft = Nft(nftImplementation.cloneDeterministic(salt));

        nft.initialize(
            createParams.name,
            createParams.symbol,
            msg.sender,
            createParams.categories,
            createParams.maxMintSupply,
            createParams.royaltyRate,
            createParams.refundParams,
            createParams.vestingParams,
            createParams.lockLpParams,
            createParams.yieldFarmParams
        );

        emit Create(address(nft));
    }

    /**
     * @notice Sets the NFT implementation.
     * @param _nftImplementation The address of the new NFT implementation.
     */
    function setNftImplementation(address _nftImplementation) external onlyOwner {
        nftImplementation = _nftImplementation;
        emit SetNftImplementation(_nftImplementation);
    }

    /**
     * @notice Sets the fee rate. The max fee rate is 10%.
     * @param _feeRate The new fee rate to 1e18 of precision (1e18 == 100%).
     */
    function setFeeRate(uint256 _feeRate) public onlyOwner {
        if (_feeRate > 0.1 * 1e18) revert FeeRateTooLarge();
        feeRate = _feeRate;
        emit SetFeeRate(_feeRate);
    }

    /**
     * @notice Withdraws the contract balance to the owner. This is used to claim protocol fees.
     */
    function withdraw() external onlyOwner {
        msg.sender.safeTransferETH(address(this).balance);
    }
}
