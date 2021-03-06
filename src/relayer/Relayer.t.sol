// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Hevm} from "../test/utils/Hevm.sol";
import {DSTest} from "ds-test/test.sol";
import {MockProvider} from "@cleanunicorn/mockprovider/src/MockProvider.sol";
import {Caller} from "../test/utils/Caller.sol";
import {Guarded} from "../guarded/Guarded.sol";
import {ICollybus} from "./ICollybus.sol";
import {Relayer} from "./Relayer.sol";
import {IRelayer} from "./IRelayer.sol";
import {IOracle} from "../oracle/IOracle.sol";
import {ChainlinkValueProvider} from "../oracle_implementations/spot_price/Chainlink/ChainlinkValueProvider.sol";
import {IChainlinkAggregatorV3Interface} from "../oracle_implementations/spot_price/Chainlink/ChainlinkAggregatorV3Interface.sol";
import {CheatCodes} from "../test/utils/CheatCodes.sol";

contract TestCollybus is ICollybus {
    mapping(bytes32 => uint256) public valueForToken;

    function updateDiscountRate(uint256 tokenId_, uint256 rate_)
        external
        override(ICollybus)
    {
        valueForToken[bytes32(uint256(tokenId_))] = rate_;
    }

    function updateSpot(address tokenAddress_, uint256 spot_)
        external
        override(ICollybus)
    {
        valueForToken[bytes32(uint256(uint160(tokenAddress_)))] = spot_;
    }
}

contract RelayerTest is DSTest {
    CheatCodes internal cheatCodes = CheatCodes(HEVM_ADDRESS);
    Relayer internal relayer;
    TestCollybus internal collybus;
    IRelayer.RelayerType internal relayerType =
        IRelayer.RelayerType.DiscountRate;

    MockProvider internal oracle;

    bytes32 private _mockTokenId;
    uint256 private _mockMinThreshold = 1;
    int256 private _oracleValue = 100 * 10**18;

    function setUp() public {
        collybus = new TestCollybus();
        oracle = new MockProvider();

        _mockTokenId = bytes32(uint256(1));

        // Set the value returned by the Oracle.
        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(_oracleValue, true)
            }),
            false
        );

        // We can use the same value as the nextValue
        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.nextValue.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(_oracleValue, true)
            }),
            false
        );
        oracle.givenSelectorReturnResponse(
            Guarded.canCall.selector,
            MockProvider.ReturnData({success: true, data: abi.encode(true)}),
            false
        );

        // Set update to return a boolean
        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.update.selector),
            MockProvider.ReturnData({success: true, data: abi.encode(true)}),
            true
        );

        relayer = new Relayer(
            address(collybus),
            relayerType,
            address(oracle),
            _mockTokenId,
            _mockMinThreshold
        );
    }

    function test_deploy() public {
        assertTrue(
            address(relayer) != address(0),
            "Relayer should be deployed"
        );
    }

    function test_check_collybus() public {
        assertEq(relayer.collybus(), address(collybus));
    }

    function test_check_relayerType() public {
        assertTrue(relayer.relayerType() == relayerType, "Invalid relayerType");
    }

    function test_check_oracle() public {
        assertTrue(
            relayer.oracle() == address(oracle),
            "Invalid oracle address"
        );
    }

    function test_check_encodedTokenId() public {
        assertTrue(
            relayer.encodedTokenId() == _mockTokenId,
            "Invalid encoded token id"
        );
    }

    function test_check_minimumPercentageDeltaValue() public {
        assertTrue(
            relayer.minimumPercentageDeltaValue() == _mockMinThreshold,
            "Invalid minimumPercentageDeltaValue"
        );
    }

    function test_canSetParam_minimumPercentageDeltaValue() public {
        // Set the minimumPercentageDeltaValue
        relayer.setParam("minimumPercentageDeltaValue", 10_00);

        // Check the minimumPercentageDeltaValue
        assertEq(relayer.minimumPercentageDeltaValue(), 10_00);
    }

    function testFail_shouldNotBeAbleToSet_invalidParam() public {
        relayer.setParam("invalidParam", 100_00);
    }

    function test_executeCalls_updateOnOracle() public {
        // Execute must call update on all oracles before pushing the values to Collybus
        relayer.execute();

        // Update was called for both oracles
        MockProvider.CallData memory cd = oracle.getCallData(0);
        assertTrue(cd.functionSelector == IOracle.update.selector);
    }

    function test_execute_updateDiscountRateInCollybus() public {
        relayer.execute();

        assertTrue(
            collybus.valueForToken(_mockTokenId) == uint256(_oracleValue),
            "Invalid discount rate relayer rate value"
        );
    }

    function test_execute_updateSpotPriceInCollybus() public {
        // Create a spot price relayer and check the spot prices in the Collybus

        bytes32 mockSpotTokenAddress = bytes32(uint256(1));
        Relayer spotPriceRelayer = new Relayer(
            address(collybus),
            IRelayer.RelayerType.SpotPrice,
            address(oracle),
            mockSpotTokenAddress,
            _mockMinThreshold
        );

        // Update the rates in collybus
        spotPriceRelayer.execute();

        assertTrue(
            collybus.valueForToken(mockSpotTokenAddress) ==
                uint256(_oracleValue),
            "Invalid spot price relayer spot value"
        );
    }

    function test_execute_doesNotUpdatesRatesInCollybusWhenDeltaIsBelowThreshold()
        public
    {
        // Threshold percentage
        uint256 thresholdPercentage = 50_00; // 50%

        relayer.setParam("minimumPercentageDeltaValue", thresholdPercentage);

        // Set the value returned by the Oracle.
        int256 initialValue = 100;
        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(initialValue, true)
            }),
            false
        );

        // Make sure the values are updated, start clean
        relayer.execute();

        // The initial value is the value we just defined
        assertEq(
            collybus.valueForToken(_mockTokenId),
            uint256(initialValue),
            "We should have the initial value"
        );

        // Update the oracle with a new value under the threshold limit
        int256 secondValue = initialValue +
            (initialValue * int256(thresholdPercentage)) /
            100_00 -
            1;
        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(secondValue, true)
            }),
            false
        );

        // Execute the relayer
        relayer.execute();

        // Make sure the new value was not pushed into Collybus
        assertEq(
            collybus.valueForToken(_mockTokenId),
            uint256(initialValue),
            "Collybus should not have been updated"
        );
    }

    function test_execute_updatesRatesInCollybusWhenDeltaIsAboveThreshold()
        public
    {
        // Threshold percentage
        uint256 thresholdPercentage = 50_00; // 50%

        relayer.setParam("minimumPercentageDeltaValue", thresholdPercentage);

        // Set the value returned by the Oracle.
        int256 initialValue = 100;
        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(initialValue, true)
            }),
            false
        );

        // Make sure the values are updated, start from `initialValue`
        relayer.execute();

        // The initial value is the value we just defined
        assertEq(
            collybus.valueForToken(_mockTokenId),
            uint256(initialValue),
            "We should have the initial value"
        );

        // Update the oracle with a new value above the threshold limit
        int256 secondValue = initialValue +
            (initialValue * int256(thresholdPercentage)) /
            100_00 +
            1;

        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(secondValue, true)
            }),
            false
        );

        // Execute the relayer
        relayer.execute();

        // Make sure the new value was pushed into Collybus
        assertEq(
            collybus.valueForToken(_mockTokenId),
            uint256(secondValue),
            "Collybus should have the new value"
        );
    }

    function test_executeWithRevert() public {
        // Call should not revert
        relayer.executeWithRevert();
    }

    function test_execute_returnsTrue_whenCollybusIsUpdated() public {
        bool executed;

        executed = relayer.execute();

        assertTrue(executed, "The relayer should return true");
    }

    function test_execute_returnsFalse_whenCollybusIsNotUpdated() public {
        bool executed;

        // The first execute should return true
        executed = relayer.execute();
        assertTrue(executed, "The relayer's execute() should return true");

        // The second execute should return false because the Collybus will not be updated
        executed = relayer.execute();
        assertTrue(
            executed == false,
            "The relayer execute() should return false"
        );
    }

    function test_execute_returnsFalse_whenOracleIsNotUpdated() public {
        // Set `update` to return `false`
        oracle.givenQueryReturnResponse(
            abi.encodePacked(IOracle.update.selector),
            MockProvider.ReturnData({success: true, data: abi.encode(false)}),
            true
        );

        // When the oracle's `update` returns `false`, the relayer's `execute` should return `false`
        bool executeReturnedValue = relayer.execute();
        assertTrue(
            executeReturnedValue == false,
            "The relayer execute() should return false"
        );
    }

    function test_executeWithRevert_shouldBeSuccessful_onFirstExecution()
        public
    {
        // Call should not revert
        relayer.executeWithRevert();
    }

    function testFail_executeWithRevert_shouldNotBeSuccessful_whenCollybusIsNotUpdated()
        public
    {
        relayer.execute();

        // Call should revert
        relayer.executeWithRevert();
    }

    function setChainlinkMockReturnedValue(
        MockProvider mockChainlinkAggregator,
        int256 value
    ) internal {
        mockChainlinkAggregator.givenQueryReturnResponse(
            abi.encodeWithSelector(
                IChainlinkAggregatorV3Interface.latestRoundData.selector
            ),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(
                    uint80(0), // roundId
                    value, // answer
                    uint256(0), // startedAt
                    uint256(0), // updatedAt
                    uint80(0) // answeredInRound
                )
            }),
            false
        );
    }

    function test_executeWithRevert_canBeUpdatedByKeepers() public {
        // For this test we will simulate an external actor that must be able to successfully update
        // the Relayer via multiple `executeWithRevert()` calls. We will do this by providing multiple
        // mocked Chainlink values and making sure that each value is properly validated and used.
        int256 firstValue = 1e18;
        int256 secondValue = 2e18;
        uint256 timeUpdateWindow = 100;

        // Test setup, create the mockChainlinkAggregator that will provide data for the Oracle
        MockProvider mockChainlinkAggregator = new MockProvider();
        mockChainlinkAggregator.givenQueryReturnResponse(
            abi.encodeWithSelector(
                IChainlinkAggregatorV3Interface.decimals.selector
            ),
            MockProvider.ReturnData({success: true, data: abi.encode(18)}),
            false
        );

        // Deploy the Chainlink Oracle with the mocked Chainlink datafeed contract
        ChainlinkValueProvider chainlinkVP = new ChainlinkValueProvider(
            timeUpdateWindow,
            address(mockChainlinkAggregator)
        );

        // Deploy the Relayer
        Relayer testRelayer = new Relayer(
            address(collybus),
            relayerType,
            address(chainlinkVP),
            _mockTokenId,
            _mockMinThreshold
        );

        // Whitelist the relayer in the oracle so it can trigger Oracle.update()
        chainlinkVP.allowCaller(chainlinkVP.ANY_SIG(), address(testRelayer));

        // Simulate a small time offset as the Oracle.lastTimestamp will start at 0 and we should not be able to update values
        uint256 timeStart = timeUpdateWindow + 1;

        // Set the Chainlink mock to return the first value
        setChainlinkMockReturnedValue(mockChainlinkAggregator, firstValue);

        // Forward time to the start of this test scenario
        cheatCodes.warp(timeStart);

        // Run the first `executeWithRevert()`, `Oracle.currentValue` and `Oracle.nextValue` will be equal to `firstValue`
        testRelayer.executeWithRevert();

        // Set the next value for the Chainlink mock datafeed
        setChainlinkMockReturnedValue(mockChainlinkAggregator, secondValue);

        // Forward time to the next window
        cheatCodes.warp(timeStart + timeUpdateWindow);

        // Call should not revert
        testRelayer.executeWithRevert();

        // Verify that the oracle was properly updated
        // The `nextValue` should now be equal to `secondValue` because of the update
        assertTrue(
            chainlinkVP.nextValue() == secondValue,
            "Invalid Oracle nextValue"
        );

        // The current oracle value should still be the first value because of the previous executeWithRevert()
        // `currentValue` and `nextValue` where initialized to `firstValue`
        (int256 value, bool isValid) = chainlinkVP.value();
        assertTrue(isValid, "Invalid Oracle value");
        assertTrue(value == firstValue, "Incorrect Oracle value");

        // Forward time to the next window
        cheatCodes.warp(timeStart + timeUpdateWindow * 2);

        // Call should not revert
        testRelayer.executeWithRevert();

        // Make sure the oracle value was updated and is now equal to `secondValue`
        (value, isValid) = chainlinkVP.value();
        assertTrue(isValid, "Invalid Oracle value");
        assertTrue(value == secondValue, "Incorrect Oracle value");
    }
}
