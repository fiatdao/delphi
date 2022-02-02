// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import {MockProvider} from "src/test/utils/MockProvider.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "src/factory/Factory.sol";

import {Guarded} from "src/guarded/Guarded.sol";
import {Oracle} from "src/oracle/Oracle.sol";
import {AggregatorOracle} from "src/aggregator/AggregatorOracle.sol";

// Relayers
import {ICollybusDiscountRateRelayer} from "src/relayer/CollybusDiscountRate/ICollybusDiscountRateRelayer.sol";
import {CollybusDiscountRateRelayer} from "src/relayer/CollybusDiscountRate/CollybusDiscountRateRelayer.sol";

import {ICollybusSpotPriceRelayer} from "src/relayer/CollybusSpotPrice/ICollybusSpotPriceRelayer.sol";
import {CollybusSpotPriceRelayer} from "src/relayer/CollybusSpotPrice/CollybusSpotPriceRelayer.sol";

contract FactoryTest is DSTest {
    Factory internal factory;

    function setUp() public {
        factory = new Factory();
    }

    function buildDiscountRateDeployData()
        internal
        returns (DiscountRateDeployData memory)
    {
        NotionalVPData memory notionalValueProvider = createNotionalVPData();

        OracleData memory notionalOracleData = OracleData({
            valueProviderData: abi.encode(notionalValueProvider),
            timeWindow: 200,
            maxValidTime: 600,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Notional)
        });

        AggregatorData memory notionalAggregator = AggregatorData({
            tokenId: 1,
            oracleData: new bytes[](1),
            requiredValidValues: 1,
            minimumThresholdValue: 10**14
        });

        notionalAggregator.oracleData[0] = abi.encode(notionalOracleData);

        ElementVPData memory elementValueProvider = createElementVPData();

        OracleData memory elementOracleData = OracleData({
            valueProviderData: abi.encode(elementValueProvider),
            timeWindow: 200,
            maxValidTime: 600,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Element)
        });

        AggregatorData memory elementAggregator = AggregatorData({
            tokenId: 2,
            oracleData: new bytes[](1),
            requiredValidValues: 1,
            minimumThresholdValue: 10**14
        });

        elementAggregator.oracleData[0] = abi.encode(elementOracleData);

        DiscountRateDeployData memory deployData;
        deployData.aggregatorData = new bytes[](2);
        deployData.aggregatorData[0] = abi.encode(elementAggregator);
        deployData.aggregatorData[1] = abi.encode(notionalAggregator);

        return deployData;
    }

    function test_deploy_oracle_createsContract(
        uint256 timeUpdateWindow_,
        uint256 maxValidTime_,
        int256 alpha_
    ) public {
        ElementVPData memory elementValueProvider = createElementVPData();

        OracleData memory elementDataOracle = OracleData({
            valueProviderData: abi.encode(elementValueProvider),
            timeWindow: timeUpdateWindow_,
            maxValidTime: maxValidTime_,
            alpha: alpha_,
            valueProviderType: uint8(Factory.ValueProviderType.Element)
        });

        AggregatorOracle aggregatorOracle = new AggregatorOracle();
        aggregatorOracle.allowCaller(
            AggregatorOracle.oracleAdd.selector,
            address(factory)
        );

        Oracle oracle = Oracle(
            factory.deployOracle(
                abi.encode(elementDataOracle),
                address(aggregatorOracle)
            )
        );

        // Make sure the Oracle was deployed
        assertTrue(address(oracle) != address(0), "Oracle should be deployed");

        // Check the Oracle's parameters
        assertEq(
            elementDataOracle.timeWindow,
            Oracle(oracle).timeUpdateWindow(),
            "Time update window should be correct"
        );
        assertEq(
            elementDataOracle.maxValidTime,
            Oracle(oracle).maxValidTime(),
            "Max valid time should be correct"
        );
        assertEq(
            elementDataOracle.alpha,
            Oracle(oracle).alpha(),
            "Alpha should be correct"
        );
    }

    function test_deploy_aggregator_createsContract() public {
        ElementVPData memory elementValueProvider = createElementVPData();

        OracleData memory elementDataOracle = OracleData({
            valueProviderData: abi.encode(elementValueProvider),
            timeWindow: 200,
            maxValidTime: 600,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Element)
        });

        AggregatorData memory elementAggregatorData;
        elementAggregatorData.tokenId = 1;
        elementAggregatorData.requiredValidValues = 1;
        elementAggregatorData.oracleData = new bytes[](1);
        elementAggregatorData.oracleData[0] = abi.encode(elementDataOracle);

        address relayerAddress = factory.deployCollybusDiscountRateRelayer(
            address(0x1234)
        );

        // Make sure the Relayer was deployed
        assertTrue(relayerAddress != address(0), "Relayer should be deployed");

        address aggregatorAddress = factory.deployAggregator(
            abi.encode(elementAggregatorData),
            relayerAddress
        );

        // Make sure the Aggregator was deployed
        assertTrue(
            aggregatorAddress != address(0),
            "Aggregator should be deployed"
        );

        AggregatorOracle aggregator = AggregatorOracle(aggregatorAddress);
        // Check if the oracles are added
        assertEq(
            aggregator.oracleCount(),
            elementAggregatorData.oracleData.length,
            "Oracle count should be correct"
        );

        // Iterate and check each oracle was deployed
        for (uint256 i = 0; i < elementAggregatorData.oracleData.length; i++) {
            assertTrue(
                aggregator.oracleAt(i) != address(0),
                "Oracle should exist"
            );
        }

        // Check the required valid values
        assertEq(
            aggregator.requiredValidValues(),
            elementAggregatorData.requiredValidValues,
            "Required valid values should be correct"
        );
    }

    function test_deploy_collybusDiscountRateRelayer_createsContract() public {
        address collybus = address(0xC0111b005);

        address relayer = factory.deployCollybusDiscountRateRelayer(collybus);

        // Make sure the CollybusDiscountRateRelayer was deployed
        assertTrue(
            relayer != address(0),
            "CollybusDiscountRateRelayer should be deployed"
        );

        // Check Collybus
        assertEq(
            address(CollybusDiscountRateRelayer(relayer).collybus()),
            collybus,
            "Collybus should be correct"
        );
    }

    function test_deploy_collybusSpotPriceRelayer_createsContract() public {
        address collybus = address(0xC01115107);

        address relayer = factory.deployCollybusSpotPriceRelayer(collybus);

        // Make sure the CollybusSpotPriceRelayer_ was deployed
        assertTrue(
            relayer != address(0),
            "CollybusSpotPriceRelayer should be deployed"
        );

        // Check Collybus
        assertEq(
            address(CollybusSpotPriceRelayer(relayer).collybus()),
            collybus,
            "Collybus should be correct"
        );
    }

    function test_deploy_fullDiscountRateArchitecture() public {
        DiscountRateDeployData
            memory deployData = buildDiscountRateDeployData();

        // Deploy the oracle architecture
        address discountRateRelayer = factory.deployDiscountRateArchitecture(
            deployData,
            address(0x1234)
        );

        // Check the creation of the discount rate relayer
        assertTrue(
            discountRateRelayer != address(0),
            "CollybusDiscountPriceRelayer should be deployed"
        );

        assertEq(
            ICollybusDiscountRateRelayer(discountRateRelayer).oracleCount(),
            deployData.aggregatorData.length,
            "Discount rate relayer invalid aggregator count"
        );
    }

    function test_deploy_addAggregator() public {
        DiscountRateDeployData
            memory deployData = buildDiscountRateDeployData();

        // Deploy the oracle architecture
        address discountRateRelayer = factory.deployDiscountRateArchitecture(
            deployData,
            address(0x1234)
        );

        // Save the current aggregator count in the Relayer
        uint256 aggregatorCount = ICollybusDiscountRateRelayer(
            discountRateRelayer
        ).oracleCount();

        // Create the Aggregator data structure that will contain a Notional Oracle
        NotionalVPData memory notionalValueProvider = NotionalVPData({
            notionalViewAddress: 0x1344A36A1B56144C3Bc62E7757377D288fDE0369,
            currencyId: 2,
            lastImpliedRateDecimals: 9,
            maturityDate: 1671840000,
            settlementDate: 1648512000
        });

        OracleData memory notionalOracleData = OracleData({
            valueProviderData: abi.encode(notionalValueProvider),
            timeWindow: 200,
            maxValidTime: 600,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Notional)
        });

        AggregatorData memory notionalAggregator = AggregatorData({
            tokenId: 3,
            oracleData: new bytes[](1),
            requiredValidValues: 1,
            minimumThresholdValue: 10**14
        });

        notionalAggregator.oracleData[0] = abi.encode(notionalOracleData);

        // Deploy the new aggregator
        address aggregatorAddress = factory.deployAggregator(
            abi.encode(notionalAggregator),
            discountRateRelayer
        );

        // The Relayer should contain an extra Aggregator/Oracle
        assertEq(
            aggregatorCount + 1,
            ICollybusDiscountRateRelayer(discountRateRelayer).oracleCount(),
            "Relayer should contain the new aggregator"
        );

        // The Relayer should contain the new aggregator
        assertTrue(
            ICollybusDiscountRateRelayer(discountRateRelayer).oracleExists(
                aggregatorAddress
            ),
            "Aggregator should exist"
        );
    }

    function test_deploy_addOracle() public {
        DiscountRateDeployData
            memory deployData = buildDiscountRateDeployData();

        // Deploy the oracle architecture
        address discountRateRelayer = factory.deployDiscountRateArchitecture(
            deployData,
            address(0x1234)
        );

        // Get the address of the first aggregator
        address firstAggregatorAddress = ICollybusDiscountRateRelayer(
            discountRateRelayer
        ).oracleAt(0);

        NotionalVPData memory notionalValueProvider = NotionalVPData({
            notionalViewAddress: 0x1344A36A1B56144C3Bc62E7757377D288fDE0369,
            currencyId: 2,
            lastImpliedRateDecimals: 9,
            maturityDate: 1671840000,
            settlementDate: 1648512000
        });

        OracleData memory notionalOracleData = OracleData({
            valueProviderData: abi.encode(notionalValueProvider),
            timeWindow: 200,
            maxValidTime: 600,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Notional)
        });

        // Cache the number of oracles in the aggregator
        uint256 oracleCount = IAggregatorOracle(firstAggregatorAddress)
            .oracleCount();

        // Create and add the oracle to the aggregator
        address oracleAddress = factory.deployOracle(
            abi.encode(notionalOracleData),
            firstAggregatorAddress
        );

        // The aggregator should contain an extra Oracle
        assertEq(
            oracleCount + 1,
            IAggregatorOracle(firstAggregatorAddress).oracleCount(),
            "Aggregator should contain an extra Oracle"
        );

        assertTrue(
            IAggregatorOracle(firstAggregatorAddress).oracleExists(oracleAddress),
            "Aggregator should contain the added Oracle"
        );
    }

    function createElementVPData() internal returns (ElementVPData memory) {
        // Set-up the needed parameters to create the ElementFi Value Provider.
        // Values used are the same as in the ElementFiValueProvider test.
        // We need to mock the decimal values for the tokens because they are
        // interrogated when the contract is created.
        MockProvider underlierMock = new MockProvider();
        underlierMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(uint8(18))
            }),
            false
        );

        MockProvider ePTokenBondMock = new MockProvider();
        ePTokenBondMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(uint8(18))
            }),
            false
        );

        MockProvider poolToken = new MockProvider();
        poolToken.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(uint8(18))
            }),
            false
        );

        ElementVPData memory elementValueProvider = ElementVPData({
            poolId: 0x6dd0f7c8f4793ed2531c0df4fea8633a21fdcff40002000000000000000000b7,
            balancerVault: address(0x12345),
            poolToken: address(poolToken),
            underlier: address(underlierMock),
            ePTokenBond: address(ePTokenBondMock),
            timeScale: 2426396518,
            maturity: 1651275535
        });

        return elementValueProvider;
    }

    function createNotionalVPData() public returns (NotionalVPData memory) {
        NotionalVPData memory notionalValueProvider = NotionalVPData({
            notionalViewAddress: 0x1344A36A1B56144C3Bc62E7757377D288fDE0369,
            currencyId: 2,
            lastImpliedRateDecimals: 9,
            maturityDate: 1671840000,
            settlementDate: 1648512000
        });
        return notionalValueProvider;
    }
}
