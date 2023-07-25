// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {LibClone} from "solady/utils/LibClone.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Nft} from "./Nft.sol";

contract BatonLaunchpad is Ownable {
    using LibClone for address;

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
        feeRate = _feeRate;
    }

    receive() external payable {}

    /**
     * @notice Creates a new NFT contract.
     * @param createParams The parameters used to create the NFT.
     * @param salt The salt used when cloning the NFT via create2 (must be unique).
     * @return nft The address of the newly created NFT contract.
     */
    function create(CreateParams memory createParams, bytes32 salt) public returns (Nft nft) {
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
    function setNftImplementation(address _nftImplementation) public onlyOwner {
        nftImplementation = _nftImplementation;
        emit SetNftImplementation(_nftImplementation);
    }

    /**
     * @notice Sets the fee rate.
     * @param _feeRate The new fee rate.
     */
    function setFeeRate(uint256 _feeRate) public onlyOwner {
        feeRate = _feeRate;
        emit SetFeeRate(_feeRate);
    }
}
