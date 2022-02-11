// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import {Hevm} from "src/test/utils/Hevm.sol";
import {Caller} from "src/test/utils/Caller.sol";
import {MockProvider} from "@cleanunicorn/mockprovider/src/MockProvider.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "src/factory/Factory.sol";
import {Guarded} from "src/guarded/Guarded.sol";
import {Oracle} from "src/oracle/Oracle.sol";
import {AggregatorOracle} from "src/aggregator/AggregatorOracle.sol";

// Contract Deployers and dependencies
import {FactoryElementFiValueProvider} from "src/factory/FactoryElementFiValueProvider.sol";
import {FactoryNotionalFinanceValueProvider} from "src/factory/FactoryNotionalFinanceValueProvider.sol";
import {FactoryYieldValueProvider} from "src/factory/FactoryYieldValueProvider.sol";
import {FactoryChainlinkValueProvider} from "src/factory/FactoryChainlinkValueProvider.sol";
import {FactoryAggregatorOracle} from "src/factory/FactoryAggregatorOracle.sol";
import {FactoryCollybusSpotPriceRelayer} from "src/factory/FactoryCollybusSpotPriceRelayer.sol";
import {FactoryCollybusDiscountRateRelayer} from "src/factory/FactoryCollybusDiscountRateRelayer.sol";
import {ChainlinkMockProvider} from "src/deploy/ChainlinkMockProvider.sol";

import {IYieldPool} from "src/oracle_implementations/discount_rate/Yield/IYieldPool.sol";
import {IChainlinkAggregatorV3Interface} from "src/oracle_implementations/spot_price/Chainlink/ChainlinkAggregatorV3Interface.sol";

// Relayers
import {ICollybusDiscountRateRelayer} from "src/relayer/CollybusDiscountRate/ICollybusDiscountRateRelayer.sol";
import {CollybusDiscountRateRelayer} from "src/relayer/CollybusDiscountRate/CollybusDiscountRateRelayer.sol";

import {ICollybusSpotPriceRelayer} from "src/relayer/CollybusSpotPrice/ICollybusSpotPriceRelayer.sol";
import {CollybusSpotPriceRelayer} from "src/relayer/CollybusSpotPrice/CollybusSpotPriceRelayer.sol";

contract FactoryTest is DSTest {
    error FactoryTest__invalidDiscountRateAggregatorType(uint256 valueType);
    error FactoryTest__invalidSpotPriceAggregatorType(uint256 valueType);

    Factory internal factory;

    FactoryElementFiValueProvider internal elementFiValueProviderFactoryMock;
    FactoryNotionalFinanceValueProvider
        internal notionalValueProviderFactoryMock;
    FactoryYieldValueProvider internal yieldValueProviderFactoryMock;
    FactoryChainlinkValueProvider internal chainlinkValueProviderFactoryMock;
    FactoryAggregatorOracle internal aggregatorOracleFactoryMock;
    FactoryCollybusDiscountRateRelayer
        internal collybusDiscountRateRelayerFactoryMock;
    FactoryCollybusSpotPriceRelayer
        internal collybusSpotPriceRelayerFactoryMock;

    function setUp() public {
        elementFiValueProviderFactoryMock = new FactoryElementFiValueProvider();
        notionalValueProviderFactoryMock = new FactoryNotionalFinanceValueProvider();
        yieldValueProviderFactoryMock = new FactoryYieldValueProvider();
        chainlinkValueProviderFactoryMock = new FactoryChainlinkValueProvider();
        aggregatorOracleFactoryMock = new FactoryAggregatorOracle();
        collybusDiscountRateRelayerFactoryMock = new FactoryCollybusDiscountRateRelayer();
        collybusSpotPriceRelayerFactoryMock = new FactoryCollybusSpotPriceRelayer();

        factory = new Factory(
            address(elementFiValueProviderFactoryMock),
            address(notionalValueProviderFactoryMock),
            address(yieldValueProviderFactoryMock),
            address(chainlinkValueProviderFactoryMock),
            address(aggregatorOracleFactoryMock),
            address(collybusDiscountRateRelayerFactoryMock),
            address(collybusSpotPriceRelayerFactoryMock)
        );
    }

    function test_deploy() public {
        // Check the factory addresses are properly set

        assertEq(
            factory.elementFiValueProviderFactory(),
            address(elementFiValueProviderFactoryMock),
            "Invalid elementFiValueProviderFactoryMock"
        );

        assertEq(
            factory.notionalValueProviderFactory(),
            address(notionalValueProviderFactoryMock),
            "Invalid notionalFiValueProviderFactory"
        );

        assertEq(
            factory.yieldValueProviderFactory(),
            address(yieldValueProviderFactoryMock),
            "Invalid yieldValueProviderFactory"
        );

        assertEq(
            factory.chainlinkValueProviderFactory(),
            address(chainlinkValueProviderFactoryMock),
            "Invalid chainLinkValueProviderFactory"
        );

        assertEq(
            factory.aggregatorOracleFactory(),
            address(aggregatorOracleFactoryMock),
            "Invalid aggregatorOracleFactory"
        );

        assertEq(
            factory.collybusDiscountRateRelayerFactory(),
            address(collybusDiscountRateRelayerFactoryMock),
            "Invalid collybusDiscountRateRelayerFactory"
        );

        assertEq(
            factory.collybusSpotPriceRelayerFactory(),
            address(collybusSpotPriceRelayerFactoryMock),
            "Invalid collybusSpotPriceRelayerFactory"
        );
    }

    function test_setPermission_CallsAllowCaller_WithCorrectArguments(
        bytes32 sig_,
        address who_
    ) public {
        // Define arguments
        MockProvider where = new MockProvider();

        // Call factory to set permission
        factory.setPermission(address(where), sig_, who_);

        // Check the destination was called correctly by the factory
        MockProvider.CallData memory cd = where.getCallData(0);
        assertEq(cd.caller, address(factory));
        assertEq(cd.functionSelector, Guarded.allowCaller.selector);
        assertEq(
            keccak256(cd.data),
            keccak256(
                abi.encodeWithSelector(Guarded.allowCaller.selector, sig_, who_)
            )
        );
    }

    function test_UnauthorizedUser_CannotSetPermission(
        address where_,
        bytes32 sig_,
        address who_
    ) public {
        // Create user
        Caller user = new Caller();

        // Call factory to set permission
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.setPermission.selector,
                address(where_),
                sig_,
                who_
            )
        );

        // Call should be unsuccessful
        assertTrue(
            ok == false,
            "Unauthorized user should not be allowed to call `setPermission`"
        );
    }

    function test_AuthorizedUser_CanSetPermission(bytes32 sig_, address who_)
        public
    {
        // Create mock
        MockProvider where = new MockProvider();

        // Create user
        Caller user = new Caller();

        // Authorize user
        factory.allowCaller(factory.setPermission.selector, address(user));

        // User calls factory to set permission
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.setPermission.selector,
                address(where),
                sig_,
                who_
            )
        );

        // Call should be successful
        assertTrue(
            ok,
            "Authorized user should be allowed to call `setPermission`"
        );
    }

    function test_removePermission_CallsBlockCaller_WithCorrectArguments(
        bytes32 sig_,
        address who_
    ) public {
        // Create mock to check correct call
        MockProvider where = new MockProvider();

        // Call factory to remove permission
        factory.removePermission(address(where), sig_, who_);

        // Check the destination was called correctly by the factory
        MockProvider.CallData memory cd = where.getCallData(0);
        assertEq(cd.caller, address(factory));
        assertEq(cd.functionSelector, Guarded.blockCaller.selector);
        assertEq(
            keccak256(cd.data),
            keccak256(
                abi.encodeWithSelector(Guarded.blockCaller.selector, sig_, who_)
            )
        );
    }

    function test_UnauthorizedUser_CannotRemovePermission(
        bytes32 sig_,
        address who_
    ) public {
        // Create mock
        MockProvider where = new MockProvider();

        // Create user
        Caller user = new Caller();

        // Call factory to remove permission
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.removePermission.selector,
                address(where),
                sig_,
                who_
            )
        );

        // Call should be unsuccessful
        assertTrue(
            ok == false,
            "Unauthorized user should not be able to call `removePermission`"
        );
    }

    function test_AuthorizedUser_CanRemovePermission(bytes32 sig_, address who_)
        public
    {
        // Create mock
        MockProvider where = new MockProvider();

        // Create user
        Caller user = new Caller();

        // Authorize user
        factory.allowCaller(factory.removePermission.selector, address(user));

        // User calls factory to remove permission
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.removePermission.selector,
                address(where),
                sig_,
                who_
            )
        );

        // Call should be successful
        assertTrue(
            ok,
            "Authorized user should be allowed to call `removePermission`"
        );
    }

    function test_deploy_ElementFiValueProvider() public {
        // Create the oracle data structure
        ElementVPData memory elementValueProvider = createElementVPData();
        OracleData memory elementDataOracle = OracleData({
            valueProviderData: abi.encode(elementValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Element)
        });

        address oracleAddress = factory.deployElementFiValueProvider(
            elementDataOracle
        );

        // Make sure the Oracle was deployed
        assertTrue(
            oracleAddress != address(0),
            "Element Oracle should be correctly deployed"
        );
    }

    function test_deploy_ElementFiValueProvider_OnlyAuthrorizedUsers() public {
        // Create the oracle data structure
        ElementVPData memory elementValueProvider = createElementVPData();
        OracleData memory elementDataOracle = OracleData({
            valueProviderData: abi.encode(elementValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Element)
        });

        Caller user = new Caller();

        // Deploy the oracle
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.deployElementFiValueProvider.selector,
                elementDataOracle
            )
        );
        assertTrue(
            ok == false,
            "Only authorized users should be able to deploy oracles"
        );
    }

    function test_deploy_NotionalFinanceValueProvider() public {
        // Create the oracle data structure
        NotionalVPData memory notionalValueProvider = createNotionalVPData();
        OracleData memory notionalDataOracle = OracleData({
            valueProviderData: abi.encode(notionalValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Notional)
        });

        address oracleAddress = factory.deployNotionalFinanceValueProvider(
            notionalDataOracle
        );

        // Make sure the Oracle was deployed
        assertTrue(
            oracleAddress != address(0),
            "Notional Oracle should be correctly deployed"
        );
    }

    function test_deploy_NotionalFinanceValueProvider_OnlyAuthrorizedUsers()
        public
    {
        // Create the oracle data structure
        NotionalVPData memory notionalValueProvider = createNotionalVPData();
        OracleData memory notionalDataOracle = OracleData({
            valueProviderData: abi.encode(notionalValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Notional)
        });

        Caller user = new Caller();

        // Deploy the oracle
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.deployNotionalFinanceValueProvider.selector,
                notionalDataOracle
            )
        );
        assertTrue(
            ok == false,
            "Only authorized users should be able to deploy oracles"
        );
    }

    function test_deploy_YieldValueProvider() public {
        // Create the oracle data structure
        YieldVPData memory yieldValueProvider = createYieldVPData();
        OracleData memory yieldDataOracle = OracleData({
            valueProviderData: abi.encode(yieldValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Yield)
        });

        address oracleAddress = factory.deployYieldValueProvider(
            yieldDataOracle
        );

        // Make sure the Oracle was deployed
        assertTrue(
            oracleAddress != address(0),
            "Yield Oracle should be correctly deployed"
        );
    }

    function test_deploy_YieldValueProvider_OnlyAuthrorizedUsers() public {
        // Create the oracle data structure
        YieldVPData memory yieldValueProvider = createYieldVPData();
        OracleData memory yieldDataOracle = OracleData({
            valueProviderData: abi.encode(yieldValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Yield)
        });

        Caller user = new Caller();

        // Deploy the oracle
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.deployYieldValueProvider.selector,
                yieldDataOracle
            )
        );
        assertTrue(
            ok == false,
            "Only authorized users should be able to deploy oracles"
        );
    }

    function test_deploy_ChainlinkValueProvider() public {
        // Create the oracle data structure
        ChainlinkVPData memory chainlinkValueProvider = createChainlinkVPData();
        OracleData memory chainlinkDataOracle = OracleData({
            valueProviderData: abi.encode(chainlinkValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Chainlink)
        });

        address oracleAddress = factory.deployChainlinkValueProvider(
            chainlinkDataOracle
        );

        // Make sure the Oracle was deployed
        assertTrue(
            oracleAddress != address(0),
            "Chainlink Oracle should be correctly deployed"
        );
    }

    function test_deploy_ChainlinkValueProvider_OnlyAuthrorizedUsers() public {
        // Create the oracle data structure
        ChainlinkVPData memory chainlinkValueProvider = createChainlinkVPData();
        OracleData memory chainlinkDataOracle = OracleData({
            valueProviderData: abi.encode(chainlinkValueProvider),
            timeWindow: 100,
            maxValidTime: 300,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Chainlink)
        });

        Caller user = new Caller();

        // Deploy the oracle
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.deployChainlinkValueProvider.selector,
                chainlinkDataOracle
            )
        );
        assertTrue(
            ok == false,
            "Only authorized users should be able to deploy oracles"
        );
    }

    function test_deploy_AggregatorOracle_forEveryValueProviderType() public {
        // Setup an array of oracle data structures for every oracle type
        OracleData[] memory oracleData = new OracleData[](
            uint256(Factory.ValueProviderType.COUNT)
        );
        oracleData[
            uint256(Factory.ValueProviderType.Element)
        ] = createElementOracleData();
        oracleData[
            uint256(Factory.ValueProviderType.Notional)
        ] = createNotionalOracleData();
        oracleData[
            uint256(Factory.ValueProviderType.Yield)
        ] = createYieldOracleData();
        oracleData[
            uint256(Factory.ValueProviderType.Chainlink)
        ] = createChainlinkOracleData();

        // The test will fail if we add a value type and we do not implement a deploy method for it
        for (
            uint256 oracleType = 0;
            oracleType < uint256(Factory.ValueProviderType.COUNT);
            oracleType++
        ) {
            // Create a new mock aggregator and allow the factory to add oracles
            AggregatorOracle aggregatorOracle = new AggregatorOracle();
            aggregatorOracle.allowCaller(
                aggregatorOracle.ANY_SIG(),
                address(factory)
            );

            // Deploy and add the oracle to the aggregator oracle
            address oracleAddress = factory.deployAggregatorOracle(
                abi.encode(oracleData[oracleType]),
                address(aggregatorOracle)
            );

            // Check that oracleAdd was called on the aggregator
            assertTrue(
                aggregatorOracle.oracleExists(oracleAddress),
                "Deployed oracle should be contained by the aggregator oracle"
            );
        }
    }

    function test_deploy_AggregatorOracle_OnlyAuthrorizedUsers() public {
        OracleData memory oracleData = createElementOracleData();

        Caller user = new Caller();
        AggregatorOracle aggregatorOracle = new AggregatorOracle();
        aggregatorOracle.allowCaller(
            aggregatorOracle.ANY_SIG(),
            address(factory)
        );

        // Deploy the oracle
        (bool ok, ) = user.externalCall(
            address(factory),
            abi.encodeWithSelector(
                factory.deployAggregatorOracle.selector,
                abi.encode(oracleData),
                address(aggregatorOracle)
            )
        );

        assertTrue(
            ok == false,
            "Only authorized users should be able to call deployAggregatorOracle"
        );
    }

    function test_deploy_DiscountRateAggregator_forEveryCompatibleValueProvider()
        public
    {
        for (
            uint256 oracleType = 0;
            oracleType < uint256(Factory.ValueProviderType.COUNT);
            oracleType++
        ) {
            CollybusDiscountRateRelayer discountRateRelayer = new CollybusDiscountRateRelayer(
                    address(0xc011b005)
                );

            discountRateRelayer.allowCaller(
                discountRateRelayer.ANY_SIG(),
                address(factory)
            );
            address aggregatorAddress = factory.deployDiscountRateAggregator(
                abi.encode(
                    createDiscountRateAggregatorData(
                        Factory.ValueProviderType(oracleType)
                    )
                ),
                address(discountRateRelayer)
            );

            assertTrue(
                aggregatorAddress != address(0),
                "Aggregator not deployed"
            );
        }
    }

    function test_deploy_DiscountRateAggregator_CheckExistanceOfOracles()
        public
    {
        CollybusDiscountRateRelayer discountRateRelayer = new CollybusDiscountRateRelayer(
                address(0xc011b005)
            );

        discountRateRelayer.allowCaller(
            discountRateRelayer.ANY_SIG(),
            address(factory)
        );

        uint256 oracleCount = 3;
        DiscountRateAggregatorData
            memory aggregator = DiscountRateAggregatorData({
                tokenId: 1,
                oracleData: new bytes[](oracleCount),
                requiredValidValues: 1,
                minimumThresholdValue: 10**14
            });

        for (
            uint256 oracleIndex = 0;
            oracleIndex < oracleCount;
            oracleIndex++
        ) {
            aggregator.oracleData[oracleIndex] = abi.encode(
                createElementOracleData()
            );
        }

        address aggregatorAddress = factory.deployDiscountRateAggregator(
            abi.encode(aggregator),
            address(discountRateRelayer)
        );

        assertEq(
            IAggregatorOracle(aggregatorAddress).oracleCount(),
            oracleCount,
            "Invalid Aggregator oracle count"
        );
    }

    function test_deploy_DiscountRateAggregator_CheckValidValues() public {
        CollybusDiscountRateRelayer discountRateRelayer = new CollybusDiscountRateRelayer(
                address(0xc011b005)
            );

        discountRateRelayer.allowCaller(
            discountRateRelayer.ANY_SIG(),
            address(factory)
        );

        uint256 validValues = 1;
        DiscountRateAggregatorData
            memory aggregator = DiscountRateAggregatorData({
                tokenId: 1,
                oracleData: new bytes[](1),
                requiredValidValues: validValues,
                minimumThresholdValue: 10**14
            });

        aggregator.oracleData[0] = abi.encode(createElementOracleData());

        address aggregatorAddress = factory.deployDiscountRateAggregator(
            abi.encode(aggregator),
            address(discountRateRelayer)
        );

        assertEq(
            AggregatorOracle(aggregatorAddress).requiredValidValues(),
            validValues,
            "Invalid required valid values"
        );
    }

    function test_deploy_SpotPriceAggregator_forEveryCompatibleValueProvider()
        public
    {
        for (
            uint256 oracleType = 0;
            oracleType < uint256(Factory.ValueProviderType.COUNT);
            oracleType++
        ) {
            CollybusSpotPriceRelayer spotPriceRelayer = new CollybusSpotPriceRelayer(
                    address(0xc011b005)
                );

            spotPriceRelayer.allowCaller(
                spotPriceRelayer.ANY_SIG(),
                address(factory)
            );
            address aggregatorAddress = factory.deploySpotPriceAggregator(
                abi.encode(
                    createSpotPriceAggregatorData(
                        Factory.ValueProviderType(oracleType)
                    )
                ),
                address(spotPriceRelayer)
            );

            assertTrue(
                aggregatorAddress != address(0),
                "Aggregator not deployed"
            );
        }
    }

    function test_deploy_SpotPriceAggregator_CheckExistanceOfOracles() public {
        // Set-up the mock providers
        AggregatorOracle mockAggregatorAddress = new AggregatorOracle();
        mockAggregatorAddress.allowCaller(
            mockAggregatorAddress.ANY_SIG(),
            address(factory)
        );

        CollybusSpotPriceRelayer spotPriceRelayer = new CollybusSpotPriceRelayer(
                address(0xc011b005)
            );

        spotPriceRelayer.allowCaller(
            spotPriceRelayer.ANY_SIG(),
            address(factory)
        );

        uint256 oracleCount = 3;
        SpotPriceAggregatorData memory aggregator = SpotPriceAggregatorData({
            tokenAddress: address(0x1234),
            oracleData: new bytes[](oracleCount),
            requiredValidValues: 1,
            minimumThresholdValue: 10**14
        });

        for (
            uint256 oracleIndex = 0;
            oracleIndex < oracleCount;
            oracleIndex++
        ) {
            aggregator.oracleData[oracleIndex] = abi.encode(
                createChainlinkOracleData()
            );
        }

        address aggregatorAddress = factory.deploySpotPriceAggregator(
            abi.encode(aggregator),
            address(spotPriceRelayer)
        );

        assertEq(
            IAggregatorOracle(aggregatorAddress).oracleCount(),
            oracleCount,
            "Invalid Aggregator oracle count"
        );
    }

    function test_deploy_SpotPriceAggregator_CheckValidValues() public {
        CollybusSpotPriceRelayer spotPriceRelayer = new CollybusSpotPriceRelayer(
                address(0xc011b005)
            );

        spotPriceRelayer.allowCaller(
            spotPriceRelayer.ANY_SIG(),
            address(factory)
        );

        uint256 validValues = 1;
        SpotPriceAggregatorData memory aggregator = SpotPriceAggregatorData({
            tokenAddress: address(0x1234),
            oracleData: new bytes[](1),
            requiredValidValues: validValues,
            minimumThresholdValue: 10**14
        });

        aggregator.oracleData[0] = abi.encode(createChainlinkOracleData());

        address aggregatorAddress = factory.deploySpotPriceAggregator(
            abi.encode(aggregator),
            address(spotPriceRelayer)
        );

        assertEq(
            AggregatorOracle(aggregatorAddress).requiredValidValues(),
            validValues,
            "Invalid required valid values"
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
    }

    function test_deploy_collybusSpotPriceRelayer_createsContract() public {
        address collybus = address(0xC01115107);
        address relayer = factory.deployCollybusSpotPriceRelayer(collybus);

        // Make sure the CollybusSpotPriceRelayer_ was deployed
        assertTrue(
            relayer != address(0),
            "CollybusSpotPriceRelayer should be deployed"
        );
    }

    function test_deploy_collybusDiscountRate_fullArchitecture() public {
        RelayerDeployData memory deployData = createDiscountRateDeployData();

        // Deploy the oracle architecture
        address discountRateRelayer = factory.deployDiscountRateArchitecture(
            abi.encode(deployData),
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

    function test_deploy_collybusDiscountRate_addAggregator() public {
        RelayerDeployData memory deployData = createDiscountRateDeployData();

        // Deploy the oracle architecture
        address discountRateRelayer = factory.deployDiscountRateArchitecture(
            abi.encode(deployData),
            address(0x1234)
        );

        // Save the current aggregator count in the Relayer
        uint256 aggregatorCount = ICollybusDiscountRateRelayer(
            discountRateRelayer
        ).oracleCount();

        // Create the Aggregator data structure that will contain a Notional Oracle
        DiscountRateAggregatorData
            memory notionalAggregator = DiscountRateAggregatorData({
                tokenId: 3,
                oracleData: new bytes[](1),
                requiredValidValues: 1,
                minimumThresholdValue: 10**14
            });

        notionalAggregator.oracleData[0] = abi.encode(
            createNotionalOracleData()
        );

        // Deploy the new aggregator
        address aggregatorAddress = factory.deployDiscountRateAggregator(
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

    function test_deploy_collybusDiscountRate_addOracle() public {
        RelayerDeployData memory deployData = createDiscountRateDeployData();

        // Deploy the oracle architecture
        address discountRateRelayer = factory.deployDiscountRateArchitecture(
            abi.encode(deployData),
            address(0x1234)
        );

        // Get the address of the first aggregator
        address firstAggregatorAddress = ICollybusDiscountRateRelayer(
            discountRateRelayer
        ).oracleAt(0);

        // Cache the number of oracles in the aggregator
        uint256 oracleCount = IAggregatorOracle(firstAggregatorAddress)
            .oracleCount();

        // Create and add the oracle to the aggregator
        address oracleAddress = factory.deployAggregatorOracle(
            abi.encode(createNotionalOracleData()),
            firstAggregatorAddress
        );

        // The aggregator should contain an extra Oracle
        assertEq(
            oracleCount + 1,
            IAggregatorOracle(firstAggregatorAddress).oracleCount(),
            "Aggregator should contain an extra Oracle"
        );

        assertTrue(
            IAggregatorOracle(firstAggregatorAddress).oracleExists(
                oracleAddress
            ),
            "Aggregator should contain the added Oracle"
        );
    }

    function test_deploy_collybusSpotPrice_fullArchitecture() public {
        RelayerDeployData memory deployData = createSpotPriceDeployData();

        // Deploy the oracle architecture
        address spotPriceRelayer = factory.deploySpotPriceArchitecture(
            abi.encode(deployData),
            address(0x1234)
        );

        // Check the creation of the discount rate relayer
        assertTrue(
            spotPriceRelayer != address(0),
            "CollybusSpotPriceRelayer should be deployed"
        );

        assertEq(
            ICollybusSpotPriceRelayer(spotPriceRelayer).oracleCount(),
            deployData.aggregatorData.length,
            "CollybusSpotPriceRelayer invalid aggregator count"
        );
    }

    function test_deploy_collybusSpotPrice_addAggregator() public {
        RelayerDeployData memory deployData = createSpotPriceDeployData();

        // Deploy the oracle architecture
        address spotPriceRelayer = factory.deploySpotPriceArchitecture(
            abi.encode(deployData),
            address(0x1234)
        );

        // Save the current aggregator count in the Relayer
        uint256 aggregatorCount = ICollybusSpotPriceRelayer(spotPriceRelayer)
            .oracleCount();

        // The first aggregator is at address 0x1, make the second one use a different address
        SpotPriceAggregatorData
            memory chainlinkAggregator = SpotPriceAggregatorData({
                tokenAddress: address(0x2),
                oracleData: new bytes[](1),
                requiredValidValues: 1,
                minimumThresholdValue: 10**14
            });

        chainlinkAggregator.oracleData[0] = abi.encode(
            createChainlinkOracleData()
        );

        // Deploy the new aggregator
        address aggregatorAddress = factory.deploySpotPriceAggregator(
            abi.encode(chainlinkAggregator),
            spotPriceRelayer
        );

        // The Relayer should contain an extra Aggregator/Oracle
        assertEq(
            aggregatorCount + 1,
            ICollybusSpotPriceRelayer(spotPriceRelayer).oracleCount(),
            "Relayer should contain the new aggregator"
        );

        // The Relayer should contain the new aggregator
        assertTrue(
            ICollybusSpotPriceRelayer(spotPriceRelayer).oracleExists(
                aggregatorAddress
            ),
            "Aggregator should exist"
        );
    }

    function test_deploy_collybusSpotPrice_addOracle() public {
        RelayerDeployData memory deployData = createSpotPriceDeployData();

        // Deploy the oracle architecture
        address spotPriceRelayer = factory.deploySpotPriceArchitecture(
            abi.encode(deployData),
            address(0x1234)
        );

        // Get the address of the first aggregator
        address firstAggregatorAddress = ICollybusSpotPriceRelayer(
            spotPriceRelayer
        ).oracleAt(0);

        // Cache the number of oracles in the aggregator
        uint256 oracleCount = IAggregatorOracle(firstAggregatorAddress)
            .oracleCount();

        // Create and add the oracle to the aggregator
        address oracleAddress = factory.deployAggregatorOracle(
            abi.encode(createChainlinkOracleData()),
            firstAggregatorAddress
        );

        // The aggregator should contain an extra Oracle
        assertEq(
            oracleCount + 1,
            IAggregatorOracle(firstAggregatorAddress).oracleCount(),
            "Aggregator should contain an extra Oracle"
        );

        assertTrue(
            IAggregatorOracle(firstAggregatorAddress).oracleExists(
                oracleAddress
            ),
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

    function createYieldVPData() internal returns (YieldVPData memory) {
        // Mock the yield pool that is needed when the value provider contract is created
        MockProvider yieldPool = new MockProvider();

        yieldPool.givenQueryReturnResponse(
            abi.encodeWithSelector(IYieldPool.getCache.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(uint112(0), uint112(0), uint32(0))
            }),
            false
        );

        yieldPool.givenQueryReturnResponse(
            abi.encodeWithSelector(IYieldPool.cumulativeBalancesRatio.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(uint256(0))
            }),
            false
        );

        YieldVPData memory yieldValueProviderData = YieldVPData({
            poolAddress: address(yieldPool),
            maturity: 1648177200,
            timeScale: 3168808781
        });

        return yieldValueProviderData;
    }

    function createElementOracleData() internal returns (OracleData memory) {
        return
            OracleData({
                valueProviderData: abi.encode(createElementVPData()),
                timeWindow: 0,
                maxValidTime: 0,
                alpha: 0,
                valueProviderType: uint8(Factory.ValueProviderType.Element)
            });
    }

    function createNotionalOracleData() internal returns (OracleData memory) {
        return
            OracleData({
                valueProviderData: abi.encode(createNotionalVPData()),
                timeWindow: 0,
                maxValidTime: 0,
                alpha: 0,
                valueProviderType: uint8(Factory.ValueProviderType.Notional)
            });
    }

    function createYieldOracleData() internal returns (OracleData memory) {
        return
            OracleData({
                valueProviderData: abi.encode(createYieldVPData()),
                timeWindow: 0,
                maxValidTime: 0,
                alpha: 0,
                valueProviderType: uint8(Factory.ValueProviderType.Yield)
            });
    }

    function createChainlinkOracleData() internal returns (OracleData memory) {
        return
            OracleData({
                valueProviderData: abi.encode(createChainlinkVPData()),
                timeWindow: 0,
                maxValidTime: 0,
                alpha: 0,
                valueProviderType: uint8(Factory.ValueProviderType.Chainlink)
            });
    }

    function createChainlinkVPData() internal returns (ChainlinkVPData memory) {
        // Set-up the needed parameters to create the Chainlink Value Provider.
        // We need to mock the decimal getter because it's interrogated when the contract is created.
        MockProvider chainlinkMock = new MockProvider();
        chainlinkMock.givenQueryReturnResponse(
            abi.encodeWithSelector(
                IChainlinkAggregatorV3Interface.decimals.selector
            ),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(uint8(8))
            }),
            false
        );

        ChainlinkVPData memory chainlinkValueProvider = ChainlinkVPData({
            chainlinkAggregatorAddress: address(chainlinkMock)
        });

        return chainlinkValueProvider;
    }

    function createDiscountRateAggregatorData(
        Factory.ValueProviderType valueType
    ) internal returns (DiscountRateAggregatorData memory) {
        DiscountRateAggregatorData
            memory aggregator = DiscountRateAggregatorData({
                tokenId: 1,
                oracleData: new bytes[](1),
                requiredValidValues: 1,
                minimumThresholdValue: 10**14
            });

        if (valueType == Factory.ValueProviderType.Element) {
            aggregator.oracleData[0] = abi.encode(createElementOracleData());
        } else if (valueType == Factory.ValueProviderType.Notional) {
            aggregator.oracleData[0] = abi.encode(createNotionalOracleData());
        } else if (valueType == Factory.ValueProviderType.Yield) {
            aggregator.oracleData[0] = abi.encode(createYieldOracleData());
        } else if (valueType == Factory.ValueProviderType.Chainlink) {
            aggregator.oracleData[0] = abi.encode(createChainlinkOracleData());
        } else {
            revert FactoryTest__invalidDiscountRateAggregatorType(
                uint256(valueType)
            );
        }

        return aggregator;
    }

    function createSpotPriceAggregatorData(Factory.ValueProviderType valueType)
        internal
        returns (SpotPriceAggregatorData memory)
    {
        SpotPriceAggregatorData memory aggregator = SpotPriceAggregatorData({
            tokenAddress: address(0x1234),
            oracleData: new bytes[](1),
            requiredValidValues: 1,
            minimumThresholdValue: 10**14
        });

        if (valueType == Factory.ValueProviderType.Element) {
            aggregator.oracleData[0] = abi.encode(createElementOracleData());
        } else if (valueType == Factory.ValueProviderType.Notional) {
            aggregator.oracleData[0] = abi.encode(createNotionalOracleData());
        } else if (valueType == Factory.ValueProviderType.Yield) {
            aggregator.oracleData[0] = abi.encode(createYieldOracleData());
        } else if (valueType == Factory.ValueProviderType.Chainlink) {
            aggregator.oracleData[0] = abi.encode(createChainlinkOracleData());
        } else {
            revert FactoryTest__invalidDiscountRateAggregatorType(
                uint256(valueType)
            );
        }

        return aggregator;
    }

    function createDiscountRateDeployData()
        internal
        returns (RelayerDeployData memory)
    {
        OracleData memory notionalOracleData = createNotionalOracleData();

        DiscountRateAggregatorData
            memory notionalAggregator = DiscountRateAggregatorData({
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

        DiscountRateAggregatorData
            memory elementAggregator = DiscountRateAggregatorData({
                tokenId: 2,
                oracleData: new bytes[](1),
                requiredValidValues: 1,
                minimumThresholdValue: 10**14
            });

        elementAggregator.oracleData[0] = abi.encode(elementOracleData);

        RelayerDeployData memory deployData;
        deployData.aggregatorData = new bytes[](2);
        deployData.aggregatorData[0] = abi.encode(elementAggregator);
        deployData.aggregatorData[1] = abi.encode(notionalAggregator);

        return deployData;
    }

    function createSpotPriceDeployData()
        internal
        returns (RelayerDeployData memory)
    {
        ChainlinkVPData memory chainlinkValueProvider = createChainlinkVPData();

        OracleData memory chainlinkOracleData = OracleData({
            valueProviderData: abi.encode(chainlinkValueProvider),
            timeWindow: 200,
            maxValidTime: 600,
            alpha: 2 * 10**17,
            valueProviderType: uint8(Factory.ValueProviderType.Chainlink)
        });

        SpotPriceAggregatorData
            memory chainlinkAggregator = SpotPriceAggregatorData({
                tokenAddress: address(0x1),
                oracleData: new bytes[](1),
                requiredValidValues: 1,
                minimumThresholdValue: 10**14
            });

        chainlinkAggregator.oracleData[0] = abi.encode(chainlinkOracleData);

        RelayerDeployData memory deployData;
        deployData.aggregatorData = new bytes[](1);
        deployData.aggregatorData[0] = abi.encode(chainlinkAggregator);
        return deployData;
    }
}
