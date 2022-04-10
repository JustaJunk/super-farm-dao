// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ISuperfluid, ISuperToken, ISuperApp} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 @title SuperFaaS - Deposit
 @notice Deposit fund and mint NFT as proof
 */
contract SuperFarmDAO is ERC721 {
    /// @dev Superfluid host
    ISuperfluid private _host;

    /// @dev Constant flow agreement class address
    IConstantFlowAgreementV1 private _cfa;

    /// @dev Reward token
    ISuperToken public _rewardToken;

    /// @dev ETH chainlink price feed
    AggregatorV3Interface private _priceFeedETH;

    /// @dev Map token ID to flow rate
    mapping(uint256 => int96) public flowRates;

    /// @dev Map token ID to initial fund
    mapping(uint256 => uint256) public initFunds;

    /// @dev NFT token counter
    uint256 public tokenCounter;

    /// @dev Price feed divisor
    int256 private _priceFeedDivisor;

    /// @dev Protocol APY
    int8 public constant PROTOCOL_APY = 10;

    /// @dev One year in sec
    int256 private constant ONE_YEAR = 60 * 60 * 24 * 365;

    /// @dev Setup ERC721 and Superfluid system
    constructor(
        string memory _name,
        string memory _symbol,
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken,
        AggregatorV3Interface priceFeedETH
    ) ERC721(_name, _symbol) {
        _host = host;
        _cfa = cfa;
        _rewardToken = acceptedToken;
        _priceFeedETH = priceFeedETH;

        tokenCounter = 0;

        _priceFeedDivisor = int256(10**priceFeedETH.decimals());

        assert(address(_host) != address(0));
        assert(address(_cfa) != address(0));
        assert(address(_rewardToken) != address(0));
    }

    event NFTIssued(uint256 tokenId, address receiver, int96 flowRate);

    /// @notice Mint an NFT as a proof of incoming flow
    function mintNFT() external payable {
        (, int256 ethPrice, , , ) = _priceFeedETH.latestRoundData();
        int96 flowRate = int96(
            ((int256(msg.value) * _priceFeedDivisor * PROTOCOL_APY) /
                ethPrice) /
                100 /
                ONE_YEAR
        );
        _issueNFT(msg.sender, flowRate);
    }

    /// @dev Mint NFT with flow rate
    function _issueNFT(address receiver, int96 flowRate) internal {
        require(receiver != address(this), "Issue to a new address");
        require(flowRate > 0, "flowRate must be positive!");

        flowRates[tokenCounter] = flowRate;
        initFunds[tokenCounter] = msg.value;
        emit NFTIssued(tokenCounter, receiver, flowRates[tokenCounter]);
        _mint(receiver, tokenCounter);
        ++tokenCounter;
    }

    /// @notice Burn NFT and redeem fund
    function burnNFT(uint256 tokenId) external {
        address receiver = ownerOf(tokenId);
        require(receiver == msg.sender, "not burn by owner");

        _burn(tokenId);
        //deletes flow to previous holder of nft & receiver of stream after it is burned
        //we will reduce flow of owner of NFT by total flow rate that was being sent to owner of this token
        _reduceFlow(receiver, flowRates[tokenId]);
        delete flowRates[tokenId];

        // redeem fund
        Address.sendValue(payable(msg.sender), initFunds[tokenId]);
        delete initFunds[tokenId];
    }

    /// @dev Transfer flow before transfer token
    function _beforeTokenTransfer(
        address oldReceiver,
        address newReceiver,
        uint256 tokenId
    ) internal override {
        require(
            !_host.isApp(ISuperApp(newReceiver)) ||
                newReceiver == address(this),
            "Receiver can not be a superApp"
        );
        _reduceFlow(oldReceiver, flowRates[tokenId]);
        _increaseFlow(newReceiver, flowRates[tokenId]);
    }

    /**************************************************************************
     * Library
     *************************************************************************/
    //this will reduce the flow or delete it
    function _reduceFlow(address to, int96 flowRate) internal {
        if (to == address(this)) return;

        (, int96 outFlowRate, , ) = _cfa.getFlow(
            _rewardToken,
            address(this),
            to
        );

        if (outFlowRate == flowRate) {
            _deleteFlow(address(this), to);
        } else if (outFlowRate > flowRate) {
            // reduce the outflow by flowRate;
            // shouldn't overflow, because we just checked that it was bigger.
            _updateFlow(to, outFlowRate - flowRate);
        }
        // won't do anything if outFlowRate < flowRate
    }

    //this will increase the flow or create it
    function _increaseFlow(address to, int96 flowRate) internal {
        (, int96 outFlowRate, , ) = _cfa.getFlow(
            _rewardToken,
            address(this),
            to
        ); //returns 0 if stream doesn't exist
        if (outFlowRate == 0) {
            _createFlow(to, flowRate);
        } else {
            // increase the outflow by flowRates[tokenId]
            _updateFlow(to, outFlowRate + flowRate);
        }
    }

    function _createFlow(address to, int96 flowRate) internal {
        if (to == address(this) || to == address(0)) return;
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.createFlow.selector,
                _rewardToken,
                to,
                flowRate,
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }

    function _updateFlow(address to, int96 flowRate) internal {
        if (to == address(this) || to == address(0)) return;
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.updateFlow.selector,
                _rewardToken,
                to,
                flowRate,
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }

    function _deleteFlow(address from, address to) internal {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.deleteFlow.selector,
                _rewardToken,
                from,
                to,
                new bytes(0) // placeholder
            ),
            "0x"
        );
    }
}
