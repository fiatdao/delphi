// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {Hevm} from "src/test/utils/Hevm.sol";
import {DSTest} from "lib/ds-test/src/test.sol";
import {MockProvider} from "src/test/utils/MockProvider.sol";
import {Caller} from "src/test/utils/Caller.sol";

import {ICollybus} from "src/relayer/ICollybus.sol";
import {CollybusDiscountRateRelayer} from "./CollybusDiscountRateRelayer.sol";
import {IOracle} from "src/oracle/IOracle.sol";
import {Oracle} from "src/oracle/Oracle.sol";
import {IValueProvider} from "src/valueprovider/IValueProvider.sol";

contract TestCollybus is ICollybus {

    mapping(uint256 => int256) public rateForTokenId;
    function updateDiscountRate(uint256 tokenId, int256 rate)
        external
        override(ICollybus)
    {
        rateForTokenId[tokenId] = rate;
    }
}

contract CollybusDiscountRateRelayerTest is DSTest {
    Hevm internal hevm = Hevm(DSTest.HEVM_ADDRESS);
    CollybusDiscountRateRelayer internal cdrr;
    TestCollybus internal collybus;

    MockProvider oracle1;

    uint256 internal oracleTimeUpdateWindow = 100; // seconds
    uint256 internal oracleMaxValidTime = 300;
    int256 internal oracleAlpha = 2 * 10**17; // 0.2

    uint256 internal mockRateId1 = 1;
    uint256 internal mockRateId1MinThreshold = 1;

    function setUp() public {
        collybus = new TestCollybus();
        cdrr = new CollybusDiscountRateRelayer(address(collybus));

        oracle1 = new MockProvider();

        // Set the value returned by Value Provider to 100
        oracle1.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(int256(100 * 10**18), true)
            }),
            false
        );

        // Add oracle with rate id
        cdrr.oracleAdd(address(oracle1), mockRateId1, mockRateId1MinThreshold);
        hevm.warp(oracleTimeUpdateWindow);
    }

    function test_deploy() public {
        assertTrue(
            address(cdrr) != address(0),
            "CollybusDiscountRateRelayer should be deployed"
        );
    }

    function test_CheckExistenceOfOracle() public {
        // Check that oracle was added
        assertTrue(
            cdrr.oracleExists(address(oracle1)),
            "Oracle should be added"
        );
    }

    function test_ReturnNumberOfOracles() public {
        // Check the number of existing oracles
        assertTrue(
            cdrr.oracleCount() == 1,
            "CollybusDiscountRateRelayer should contain 1 oracle."
        );
    }

    function test_AddOracle() public {
        // Create a new address since the oracle is not checked for validity in anyway
        address newOracle = address(0x1);
        uint256 mockRateId2 = mockRateId1 + 1;

        // Add the oracle
        cdrr.oracleAdd(newOracle, mockRateId2, mockRateId1MinThreshold);
    }

    function testFail_AddOracle_ShouldNotAllowDuplicateOracles() public {
        // Attemt to add the same oracle again
        cdrr.oracleAdd(address(oracle1), mockRateId1, mockRateId1MinThreshold);
    }

    function testFail_AddOracle_ShouldNotAllowDuplicateRates() public {
        // We can use any address, the oracle will not be interogated on add.
        address newOracle = address(0x1);
        // Add a new oracle that has the same rate id as the previously added oracle.
        cdrr.oracleAdd(address(newOracle), mockRateId1, mockRateId1MinThreshold);
    }

    function test_AddOracle_OnlyAuthorizedUserShouldBeAbleToAdd() public {
        Caller user = new Caller();

        address newOracle = address(0x1);
        uint256 mockRateId2 = mockRateId1 + 1;
        uint256 mockRateId2MinThreshold = mockRateId1MinThreshold;
        // Add the oracle
        (bool ok, ) = user.externalCall(
            address(cdrr),
            abi.encodeWithSelector(
                cdrr.oracleAdd.selector,
                newOracle,
                mockRateId2,
                mockRateId2MinThreshold
            )
        );
        assertTrue(
            ok == false,
            "Only authorized users should be able to add oracles"
        );
    }

    function test_RemoveOracle_DeletesOracle() public {
        // Remove the only oracle.
        cdrr.oracleRemove(address(oracle1));

        // Relayer should be empty
        assertTrue(
            cdrr.oracleCount() == 0,
            "CollybusDiscountRateRelayer should be empty"
        );
    }

    function testFail_RemoveOracle_ShouldFailIfOracleDoesNotExist() public {
        address newOracle = address(0x1);

        // Attempt to remove oracle that does not exist.
        cdrr.oracleRemove(newOracle);
    }

    function test_RemoveOracle_OnlyAuthorizedUserShouldBeAbleToRemove() public {
        Caller user = new Caller();

        // Add the oracle
        (bool ok, ) = user.externalCall(
            address(cdrr),
            abi.encodeWithSelector(cdrr.oracleRemove.selector, address(oracle1))
        );
        assertTrue(
            ok == false,
            "Only authorized users should be able to add oracles"
        );
    }

    function test_checkCalls_returnsTrueWhenUpdateNeeded() public {
        bool mustUpdate = cdrr.check();
        assertTrue(mustUpdate);
    }

    function test_checkCallsUpdate_onlyOnFirstUpdatableOracle() public {
        MockProvider oracleValueProvider2 = new MockProvider();
        Oracle oracle2 = new Oracle(
            address(oracleValueProvider2),
            oracleTimeUpdateWindow,
            oracleMaxValidTime,
            oracleAlpha
        );
        // Set the value returned by Value Provider to 100
        oracleValueProvider2.givenQueryReturnResponse(
            abi.encodePacked(IValueProvider.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(int256(10 * 10**18))
            }),
            false
        );

        uint256 mockRateId2 = mockRateId1 + 1;
        uint256 mockRateId2MinThreshold = mockRateId1MinThreshold;
        // Add oracle with rate id
        cdrr.oracleAdd(address(oracle2), mockRateId2, mockRateId2MinThreshold);
        hevm.warp(oracleTimeUpdateWindow);

        // Check will search for at least one updatable oracle, which in our case is the first one in the list
        // therefore, the first oracle will be updated but the second will not.
        cdrr.check();

        (int256 value1, bool valid1) = IOracle(address(oracle1)).value();
        assertTrue(valid1);
        assertTrue(value1 == int256(100 * 10**18));

        (int256 value2, bool valid2) = IOracle(address(oracle2)).value();
        assertTrue(valid2 == false);
        assertTrue(value2 == 0);
    }

    function test_checkCalls_returnsFalseAfterExecute() public {
        bool checkBeforeUpdate = cdrr.check();
        assertTrue(checkBeforeUpdate);

        cdrr.execute();

        bool checkAfterUpdate = cdrr.check();
        assertTrue(checkAfterUpdate == false);
    }

    function test_executeCalls_updateOnAllOracles() public {
        MockProvider oracleValueProvider2 = new MockProvider();
        Oracle oracle2 = new Oracle(
            address(oracleValueProvider2),
            oracleTimeUpdateWindow,
            oracleMaxValidTime,
            oracleAlpha
        );
        // Set the value returned by Value Provider to 100
        oracleValueProvider2.givenQueryReturnResponse(
            abi.encodePacked(IValueProvider.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(int256(1 * 10**18))
            }),
            false
        );

        uint256 mockRateId2 = mockRateId1 + 1;
        uint256 mockRateId2MinThreshold = mockRateId1MinThreshold;
        // Add oracle with rate id
        cdrr.oracleAdd(address(oracle2), mockRateId2, mockRateId2MinThreshold);
        hevm.warp(oracleTimeUpdateWindow);

        // Execute must call update on all oracles before pushing the values to Collybus.
        cdrr.check();
        cdrr.execute();

        (int256 value1, bool valid1) = IOracle(address(oracle1)).value();
        assertTrue(valid1);
        assertTrue(value1 == int256(100 * 10**18));

        (int256 value2, bool valid2) = IOracle(address(oracle2)).value();
        assertTrue(valid2);
        assertTrue(value2 == int256(1 * 10**18));
    }

    function test_execute_UpdatesRatesInCollybus() public {
        MockProvider oracle2 = new MockProvider();

        // Set the value returned by Value Provider to 10
        oracle2.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(int256(10 * 10**18), true)
            }),
            false
        );

        uint256 mockRateId2 = mockRateId1 + 1;
        uint256 mockRateId2MinThreshold = mockRateId1MinThreshold;
        // Add oracle with rate id
        cdrr.oracleAdd(address(oracle2), mockRateId2, mockRateId2MinThreshold);
        hevm.warp(oracleTimeUpdateWindow);

        // Execute must call update on all oracles before pushing the values to Collybus.
        bool mustUpdate = cdrr.check();
        if (mustUpdate) cdrr.execute();

        assertTrue(collybus.rateForTokenId(mockRateId1) == int256(100* 10**18));
        assertTrue(collybus.rateForTokenId(mockRateId2) == int256(10* 10**18));
    }

    function test_execute_DoesNotUpdatesRatesInCollybusWhenDeltaIsBelowThreshold() public {
        MockProvider oracle2 = new MockProvider();

        int256 oracle2InitialValue = int256(10 * 10**18);
        // Set the value returned by Value Provider to 10
        oracle2.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(oracle2InitialValue, true)
            }),
            false
        );

        uint256 mockRateId2 = mockRateId1 + 1;
        uint256 mockRateId2MinThreshold = 1 * 10**18;
        // Add oracle with rate id
        cdrr.oracleAdd(address(oracle2), mockRateId2, mockRateId2MinThreshold);
        hevm.warp(oracleTimeUpdateWindow);

        // Execute must call update on all oracles before pushing the values to Collybus.
        cdrr.check();
        cdrr.execute();

        int256 oracle1NewValue = int256(10 * 10**18);
        oracle1.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(oracle1NewValue, true)
            }),
            false
        );

        // Make the second value returned by the oracle to be just lower than the minimum threshold
        int256 oracle2NewValue = oracle2InitialValue + int256(mockRateId2MinThreshold) - 1;
        oracle2.givenQueryReturnResponse(
            abi.encodePacked(IOracle.value.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(oracle2NewValue, true)
            }),
            false
        );

        hevm.warp(oracleTimeUpdateWindow);

        cdrr.execute();

        // Rate 1 from oracle 1 will be updated with the new value because the delta was bigger than the minimum threshold
        assertTrue(collybus.rateForTokenId(mockRateId1) == oracle1NewValue);
        
        // Rate 2 from oracle 2 will NOT be updated because the delta is smaller
        assertTrue(collybus.rateForTokenId(mockRateId2) == oracle2InitialValue);
    }
}
