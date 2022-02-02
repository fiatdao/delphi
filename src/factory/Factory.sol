// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IOracle} from "src/oracle/IOracle.sol";
import {Oracle} from "src/oracle/Oracle.sol";
import {AggregatorOracle} from "src/aggregator/AggregatorOracle.sol";
import {IAggregatorOracle} from "src/aggregator/IAggregatorOracle.sol";

// Value providers
import {ElementFiValueProvider} from "src/oracle_implementations/discount_rate/ElementFi/ElementFiValueProvider.sol";
import {NotionalFinanceValueProvider} from "src/oracle_implementations/discount_rate/NotionalFinance/NotionalFinanceValueProvider.sol";
import {ChainLinkValueProvider} from "src/oracle_implementations/spot_price/Chainlink/ChainLinkValueProvider.sol";

// Relayers
import {ICollybusDiscountRateRelayer} from "src/relayer/CollybusDiscountRate/ICollybusDiscountRateRelayer.sol";
import {CollybusDiscountRateRelayer} from "src/relayer/CollybusDiscountRate/CollybusDiscountRateRelayer.sol";
import {ICollybusSpotPriceRelayer} from "src/relayer/CollybusSpotPrice/ICollybusSpotPriceRelayer.sol";
import {CollybusSpotPriceRelayer} from "src/relayer/CollybusSpotPrice/CollybusSpotPriceRelayer.sol";

import {Guarded} from "src/guarded/Guarded.sol";

/// @notice Data structure that wraps data needed to deploy an Element Value Provider contract
struct ElementVPData {
    bytes32 poolId;
    address balancerVault;
    address poolToken;
    address underlier;
    address ePTokenBond;
    int256 timeScale;
    uint256 maturity;
}

/// @notice Data structure that wraps data needed to deploy an Notional Value Provider contract
struct NotionalVPData {
    address notionalViewAddress;
    uint16 currencyId;
    uint256 lastImpliedRateDecimals;
    uint256 maturityDate;
    uint256 settlementDate;
}

/// @notice Data structure that wraps data needed to deploy a Chainlink spot price value provider
struct ChainlinkVPData {
    address chainlinkAggregatorAddress;
}

/// @notice Data structure that wraps needed data to deploy an Oracle contract
/// @dev The value provider data field is a abi.encoded struct based on the given providerType
/// @dev The Factory will revert if the providerType is not found
struct OracleData {
    bytes valueProviderData;
    uint8 valueProviderType;
    uint256 timeWindow;
    uint256 maxValidTime;
    int256 alpha;
}

/// @notice Data structure that wraps needed data to deploy an Oracle Aggregator contract
/// @dev The oracleData array field contains abi.encoded OracleData structures
/// @dev Factory will revert if the requiredValidValues is bigger than the oracleData item count
struct DiscountRateAggregatorData {
    uint256 tokenId;
    bytes[] oracleData;
    uint256 requiredValidValues;
    uint256 minimumThresholdValue;
}

/// @notice Data structure that wraps needed data to deploy an Oracle Aggregator contract
/// @dev The oracleData field contains a abi.encoded OracleData structure
///      We only have one oracle per aggregator as we trust chainlink as the single source or truth
/// @dev Factory will revert if the requiredValidValues is bigger than the oracleData item count
struct SpotPriceAggregatorData {
    address tokenAddress;
    bytes oracleData;
    uint256 minimumThresholdValue;
}

/// @notice Data structure that wraps needed data to deploy a full Relayer architecture
/// @dev The aggregatorData field contains abi.encoded DiscountRateAggregatorData or SpotPriceAggregatorData structures
/// @dev Factory will revert if the aggregators do not contain unique tokenId's
struct RelayerDeployData {
    bytes[] aggregatorData;
}

contract Factory is Guarded {
    // @notice Emitter when the collybus address is address(0)
    error Factory__deployDiscountRateArchitecture_invalidCollybusAddress();

    // @notice Emitter when the collybus address is address(0)
    error Factory__deploySpotPriceArchitecture_invalidCollybusAddress();

    // @notice Emitted if no value provider is found for given providerType
    error Factory__deployValueProvider_invalidValueProviderType();

    enum ValueProviderType {
        Notional,
        Element,
        Chainlink
    }

    /// @notice Deploys an Element Finance Value Provider
    /// @dev For more information about the params please check the Value Provider Contract
    /// todo: add the master github path to contract
    /// @return Returns the address of the new value provider
    function deployElementFiValueProvider(
        // Oracle params
        OracleData memory oracleParams
    ) public checkCaller returns (address) {
        ElementVPData memory elementParams = abi.decode(
            oracleParams.valueProviderData,
            (ElementVPData)
        );

        ElementFiValueProvider elementFiValueProvider = new ElementFiValueProvider(
                oracleParams.timeWindow,
                oracleParams.maxValidTime,
                oracleParams.alpha,
                elementParams.poolId,
                elementParams.balancerVault,
                elementParams.poolToken,
                elementParams.underlier,
                elementParams.ePTokenBond,
                elementParams.timeScale,
                elementParams.maturity
            );

        return address(elementFiValueProvider);
    }

    /// @notice Deploys an Notional Finance Value Provider
    /// @dev For more information about the params please check the Value Provider Contract
    /// todo: add the master github path to contract
    /// @return Returns the address of the new value provider
    function deployNotionalFinanceValueProvider(
        // Oracle params
        OracleData memory oracleParams
    ) public checkCaller returns (address) {
        NotionalVPData memory notionalParams = abi.decode(
            oracleParams.valueProviderData,
            (NotionalVPData)
        );

        NotionalFinanceValueProvider notionalFinanceValueProvider = new NotionalFinanceValueProvider(
                oracleParams.timeWindow,
                oracleParams.maxValidTime,
                oracleParams.alpha,
                notionalParams.notionalViewAddress,
                notionalParams.currencyId,
                notionalParams.lastImpliedRateDecimals,
                notionalParams.maturityDate,
                notionalParams.settlementDate
            );

        return address(notionalFinanceValueProvider);
    }

    function deployChainlinkValueProvider(
        // Oracle params
        OracleData memory oracleParams
    ) public checkCaller returns (address) {
        ChainlinkVPData memory chainlinkParams = abi.decode(
            oracleParams.valueProviderData,
            (ChainlinkVPData)
        );

        ChainLinkValueProvider chainlinkValueProvider = new ChainLinkValueProvider(
                oracleParams.timeWindow,
                oracleParams.maxValidTime,
                oracleParams.alpha,
                chainlinkParams.chainlinkAggregatorAddress
            );

        return address(chainlinkValueProvider);
    }

    /// @notice Deploys a new Oracle and adds it to an Aggregator
    /// @param oracleDataEncoded_ Abi encoded Oracle data structure
    /// @param aggregatorAddress_ The aggregator address that will contain the created Oracle
    /// @dev Reverts if the encoded struct can not be decoded
    /// @return Returns the address of the new Oracle
    function deployOracle(
        bytes memory oracleDataEncoded_,
        address aggregatorAddress_
    ) public checkCaller returns (address) {
        // Decode the oracle data
        OracleData memory oracleData = abi.decode(
            oracleDataEncoded_,
            (OracleData)
        );

        address oracleAddress = address(0);
        if (oracleData.valueProviderType == uint8(ValueProviderType.Element)) {
            // Create and return the value provider
            oracleAddress = deployElementFiValueProvider(oracleData);
        } else if (
            oracleData.valueProviderType == uint8(ValueProviderType.Notional)
        ) {
            // Create and return the value provider
            oracleAddress = deployNotionalFinanceValueProvider(oracleData);
        } else if (
            oracleData.valueProviderType == uint8(ValueProviderType.Chainlink)
        ) {
            // Create and return the value provider
            oracleAddress = deployChainlinkValueProvider(oracleData);
        } else {
            // Revert if the value provider type is not supported
            revert Factory__deployValueProvider_invalidValueProviderType();
        }

        // Add the oracle to the Aggregator Oracle
        IAggregatorOracle(aggregatorAddress_).oracleAdd(oracleAddress);

        return oracleAddress;
    }

    /// @notice Deploys a new Aggregator and adds it to a Relayer
    /// @param aggregatorDataEncoded_ Abi encoded Oracle data structure
    /// @param discountRateRelayerAddress_ The address of the discount rate relayer where we will add the aggregator
    /// @dev Reverts if the encoded struct can not be decoded
    /// @return Returns the address of the new Aggregator
    function deployDiscountRateAggregator(
        bytes memory aggregatorDataEncoded_,
        address discountRateRelayerAddress_
    ) public checkCaller returns (address) {
        // Create the aggregator contract
        AggregatorOracle aggregatorOracle = new AggregatorOracle();

        // Decode each input notional aggregator structure
        DiscountRateAggregatorData memory aggData = abi.decode(
            aggregatorDataEncoded_,
            (DiscountRateAggregatorData)
        );

        // Iterate and deploy each oracle
        uint256 oracleCount = aggData.oracleData.length;
        for (
            uint256 oracleIndex = 0;
            oracleIndex < oracleCount;
            oracleIndex++
        ) {
            deployOracle(
                aggData.oracleData[oracleIndex],
                address(aggregatorOracle)
            );
        }

        // Set the minimum required valid values for the aggregator
        // Reverts if the requiredValidValues is bigger than the oracleCount
        aggregatorOracle.setParam(
            "requiredValidValues",
            aggData.requiredValidValues
        );

        // Add the aggregator to the relayer
        // Reverts if the tokenId is not unique
        // Revert if the address of the Aggregator is already used
        ICollybusDiscountRateRelayer(discountRateRelayerAddress_).oracleAdd(
            address(aggregatorOracle),
            aggData.tokenId,
            aggData.minimumThresholdValue
        );

        return address(aggregatorOracle);
    }

    /// @notice Deploys a new Aggregator and adds it to a Relayer
    /// @param aggregatorDataEncoded_ Abi encoded Oracle data structure
    /// @param spotPriceRelayerAddress_ The address of the spot price relayer where we will add the aggregator
    /// @dev Reverts if the encoded struct can not be decoded
    /// @return Returns the address of the new Aggregator
    function deploySpotPriceAggregator(
        bytes memory aggregatorDataEncoded_,
        address spotPriceRelayerAddress_
    ) public checkCaller returns (address) {
        // Create the aggregator contract
        AggregatorOracle aggregatorOracle = new AggregatorOracle();

        // Decode each input notional aggregator structure
        SpotPriceAggregatorData memory aggData = abi.decode(
            aggregatorDataEncoded_,
            (SpotPriceAggregatorData)
        );

        deployOracle(aggData.oracleData, address(aggregatorOracle));

        // Add the aggregator to the relayer
        // Reverts if the tokenAddress is not unique
        // Revert if the address of the Aggregator is already used
        ICollybusSpotPriceRelayer(spotPriceRelayerAddress_).oracleAdd(
            address(aggregatorOracle),
            aggData.tokenAddress,
            aggData.minimumThresholdValue
        );

        return address(aggregatorOracle);
    }

    /// @notice Deploys a new Discount Rate Relayer
    /// @param collybus_ Address for the collybus
    /// @return Returns the address of the Relayer
    function deployCollybusDiscountRateRelayer(address collybus_)
        public
        checkCaller
        returns (address)
    {
        CollybusDiscountRateRelayer discountRateRelayer = new CollybusDiscountRateRelayer(
                collybus_
            );
        return address(discountRateRelayer);
    }

    /// @notice Deploys a new Spot Price Relayer
    /// @param collybus_ Address for the collybus
    /// @return Returns the address of the Relayer
    function deployCollybusSpotPriceRelayer(address collybus_)
        public
        checkCaller
        returns (address)
    {
        CollybusSpotPriceRelayer spotPriceRelayer = new CollybusSpotPriceRelayer(
                collybus_
            );
        return address(spotPriceRelayer);
    }

    /// @notice Deploys a full Discount Rate Relayer architecture, can contain Aggregator Oracles and Oracles
    /// @param discountRateRelayerDataEncoded_ Abi encoded RelayerDeployData struct
    /// @param collybusAddress_ Collybus address.
    /// @dev Reverts on dependencies checks and conditions.
    /// @return Returns the address of the Discount Rate Relayer
    function deployDiscountRateArchitecture(
        RelayerDeployData memory discountRateRelayerDataEncoded_,
        address collybusAddress_
    ) public checkCaller returns (address) {
        // The Collybus address is needed in order to deploy the Discount Rate Relayer
        if (collybusAddress_ == address(0)) {
            revert Factory__deployDiscountRateArchitecture_invalidCollybusAddress();
        }

        // Create the relayer and cache the address
        address discountRateRelayerAddress = deployCollybusDiscountRateRelayer(
            collybusAddress_
        );

        // Iterate and deploy each aggregator
        uint256 aggCount = discountRateRelayerDataEncoded_
            .aggregatorData
            .length;
        for (uint256 aggIndex = 0; aggIndex < aggCount; aggIndex++) {
            deployDiscountRateAggregator(
                discountRateRelayerDataEncoded_.aggregatorData[aggIndex],
                discountRateRelayerAddress
            );
        }

        return discountRateRelayerAddress;
    }

    /// @notice Deploys a full Spot Price Relayer architecture, can contain Aggregator Oracles and Oracles
    /// @param spotPriceRelayerDataEncoded_ Abi encoded RelayerDeployData struct
    /// @param collybusAddress_ Collybus address.
    /// @dev Reverts on dependencies checks and conditions.
    /// @return Returns the address of the Spot Price Relayer
    function deploySpotPriceArchitecture(
        RelayerDeployData memory spotPriceRelayerDataEncoded_,
        address collybusAddress_
    ) public checkCaller returns (address) {
        // The Collybus address is needed in order to deploy the Spot Price Rate Relayer
        if (collybusAddress_ == address(0)) {
            revert Factory__deploySpotPriceArchitecture_invalidCollybusAddress();
        }

        // Create the relayer and cache the address
        address spotPriceRelayerAddress = deployCollybusSpotPriceRelayer(
            collybusAddress_
        );

        // Iterate and deploy each aggregator
        uint256 aggCount = spotPriceRelayerDataEncoded_.aggregatorData.length;
        for (uint256 aggIndex = 0; aggIndex < aggCount; aggIndex++) {
            deploySpotPriceAggregator(
                spotPriceRelayerDataEncoded_.aggregatorData[aggIndex],
                spotPriceRelayerAddress
            );
        }

        return spotPriceRelayerAddress;
    }
}
