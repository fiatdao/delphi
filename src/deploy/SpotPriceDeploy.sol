// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "src/oracle_implementations/discount_rate/ElementFi/IVault.sol";
import {RelayerDeployData, SpotPriceAggregatorData, OracleData, ChainlinkVPData, Factory} from "src/factory/Factory.sol";

import "lib/prb-math/contracts/PRBMathSD59x18.sol";

contract SpotPriceDeploy {
    function createDeployData(address chainlinkDataFeedAddress_)
        external
        view
        returns (bytes memory)
    {
        ChainlinkVPData memory chainlinkValueProvider = ChainlinkVPData({
            chainlinkAggregatorAddress: chainlinkDataFeedAddress_
        });

        OracleData memory chainlinkOracleData = OracleData({
            valueProviderData: abi.encode(chainlinkValueProvider),
            timeWindow: 60,
            maxValidTime: 600,
            alpha: 0,
            valueProviderType: uint8(Factory.ValueProviderType.Chainlink)
        });

        SpotPriceAggregatorData
            memory chainlinkAggregator = SpotPriceAggregatorData({
                tokenAddress: address(0x78dEca24CBa286C0f8d56370f5406B48cFCE2f86),
                oracleData: new bytes[](1),
                requiredValidValues: 1,
                minimumThresholdValue: 0
            });

        chainlinkAggregator.oracleData[0] = abi.encode(chainlinkOracleData);

        RelayerDeployData memory deployData;
        deployData.aggregatorData = new bytes[](1);
        deployData.aggregatorData[0] = abi.encode(chainlinkAggregator);

        return abi.encode(deployData);
    }
}