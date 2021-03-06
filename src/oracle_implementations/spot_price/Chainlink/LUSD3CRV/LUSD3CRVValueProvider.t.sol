// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "ds-test/test.sol";
import "../../../../test/utils/Caller.sol";
import {CheatCodes} from "../../../../test/utils/CheatCodes.sol";
import {MockProvider} from "@cleanunicorn/mockprovider/src/MockProvider.sol";

import {IChainlinkAggregatorV3Interface} from "../ChainlinkAggregatorV3Interface.sol";
import {LUSD3CRVValueProvider} from "./LUSD3CRVValueProvider.sol";
import {ICurvePool} from "./ICurvePool.sol";

contract LUSD3CRVValueProviderTest is DSTest {
    CheatCodes internal cheatCodes = CheatCodes(HEVM_ADDRESS);

    MockProvider internal curve3PoolMock;
    MockProvider internal curve3PoolTokenMock;
    MockProvider internal curveLUSD3CRVPoolMock;

    MockProvider internal mockChainlinkUSDC;
    MockProvider internal mockChainlinkDAI;
    MockProvider internal mockChainlinkUSDT;
    MockProvider internal mockChainlinkLUSD;

    int256 private _curve3poolVirtualPrice = 1020628557740573240;
    int256 private _lusd3PoolVirtualPrice = 1012508837937838125;

    int256 private _lusdPrice = 100102662;
    int256 private _usdcPrice = 100000298;
    int256 private _daiPrice = 100100000;
    int256 private _usdtPrice = 100030972;

    LUSD3CRVValueProvider internal lusd3ValueProvider;

    function initChainlinkMockProvider(
        MockProvider chainlinkMock_,
        int256 value_,
        uint256 decimals_
    ) private {
        chainlinkMock_.givenQueryReturnResponse(
            abi.encodeWithSelector(
                IChainlinkAggregatorV3Interface.latestRoundData.selector
            ),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(
                    uint80(36893488147419103548), // roundId
                    value_,
                    uint256(1642615905), // startedAt
                    uint256(1642615905), // updatedAt
                    uint80(36893488147419103548) // answeredInRound
                )
            }),
            false
        );
        chainlinkMock_.givenQueryReturnResponse(
            abi.encodeWithSelector(
                IChainlinkAggregatorV3Interface.decimals.selector
            ),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(decimals_)
            }),
            false
        );
    }

    function setUp() public {
        curve3PoolMock = new MockProvider();
        curve3PoolMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ICurvePool.get_virtual_price.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(_curve3poolVirtualPrice)
            }),
            false
        );
        curve3PoolMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({success: true, data: abi.encode(18)}),
            false
        );

        curve3PoolTokenMock = new MockProvider();
        curve3PoolTokenMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({success: true, data: abi.encode(18)}),
            false
        );

        curveLUSD3CRVPoolMock = new MockProvider();
        curveLUSD3CRVPoolMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ICurvePool.get_virtual_price.selector),
            MockProvider.ReturnData({
                success: true,
                data: abi.encode(_lusd3PoolVirtualPrice)
            }),
            false
        );
        curveLUSD3CRVPoolMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({success: true, data: abi.encode(18)}),
            false
        );

        mockChainlinkLUSD = new MockProvider();
        initChainlinkMockProvider(mockChainlinkLUSD, _lusdPrice, 8);

        mockChainlinkUSDC = new MockProvider();
        initChainlinkMockProvider(mockChainlinkUSDC, _usdcPrice, 8);

        mockChainlinkDAI = new MockProvider();
        initChainlinkMockProvider(mockChainlinkDAI, _daiPrice, 8);

        mockChainlinkUSDT = new MockProvider();
        initChainlinkMockProvider(mockChainlinkUSDT, _usdtPrice, 8);

        lusd3ValueProvider = new LUSD3CRVValueProvider(
            // Oracle arguments
            // Time update window
            100,
            // Chainlink arguments
            address(curve3PoolMock),
            address(curve3PoolTokenMock),
            address(curveLUSD3CRVPoolMock),
            address(mockChainlinkLUSD),
            address(mockChainlinkUSDC),
            address(mockChainlinkDAI),
            address(mockChainlinkUSDT)
        );
    }

    function test_deploy() public {
        assertTrue(address(lusd3ValueProvider) != address(0));
    }

    function test_token_decimals() public {
        assertTrue(
            lusd3ValueProvider.decimalsLUSD() == 8,
            "Invalid LUSD Decimals"
        );
        assertTrue(
            lusd3ValueProvider.decimalsUSDC() == 8,
            "Invalid USDC Decimals"
        );
        assertTrue(
            lusd3ValueProvider.decimalsDAI() == 8,
            "Invalid DAI Decimals"
        );
        assertTrue(
            lusd3ValueProvider.decimalsUSDT() == 8,
            "Invalid USDT Decimals"
        );
    }

    function test_curve_pools() public {
        assertEq(
            lusd3ValueProvider.curve3Pool(),
            address(curve3PoolMock),
            "Invalid Curve3Pool"
        );
        assertEq(
            lusd3ValueProvider.curveLUSD3Pool(),
            address(curveLUSD3CRVPoolMock),
            "Invalid LUSD3CRV Curve Pool"
        );
    }

    function test_chainlink_feeds() public {
        assertEq(
            lusd3ValueProvider.chainlinkLUSD(),
            address(mockChainlinkLUSD),
            "Invalid LUSD Chainlink Feed"
        );
        assertEq(
            lusd3ValueProvider.chainlinkUSDC(),
            address(mockChainlinkUSDC),
            "Invalid USDC Chainlink Feed"
        );
        assertEq(
            lusd3ValueProvider.chainlinkDAI(),
            address(mockChainlinkDAI),
            "Invalid DAI Chainlink Feed"
        );
        assertEq(
            lusd3ValueProvider.chainlinkUSDT(),
            address(mockChainlinkUSDT),
            "Invalid USDT Chainlink Feed"
        );
    }

    function test_getValue() public {
        // Expected value is the value sent by the mock provider in 10**18 precision
        // The expect value was computed with this formula:
        // solhint-disable-next-line
        // https://www.wolframalpha.com/input?i2d=true&i=%5C%2840%29Divide%5B1012508837937838125%2CPower%5B10%2C18%5D%5D%5C%2841%29+*+minimum%5C%2840%29Divide%5B100102662%2CPower%5B10%2C8%5D%5D%5C%2844%29%5C%2840%29+Divide%5B1020628557740573240%2CPower%5B10%2C18%5D%5D+*+Divide%5Bminimum%5C%2840%29100030972%5C%2844%29100100000%5C%2844%29100000298%5C%2841%29%2CPower%5B10%2C8%5D%5D%5C%2841%29%5C%2841%29
        int256 expectedValue = 1013548299761041868;
        // Computed value based on the parameters that are sent via the mock provider
        int256 value = lusd3ValueProvider.getValue();

        assertTrue(value == expectedValue);
    }

    function test_description() public {
        string memory expectedDescription = "LUSD3CRV";
        string memory desc = lusd3ValueProvider.description();
        assertTrue(
            keccak256(abi.encodePacked(desc)) ==
                keccak256(abi.encodePacked(expectedDescription))
        );
    }

    function test_deploy_shouldRevertWithInvalidCurve3TokenDecimals() public {
        // Update the mock to return an unsupported decimal number
        curve3PoolTokenMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({success: true, data: abi.encode(1)}),
            false
        );

        // Set the expected error for the revert
        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                LUSD3CRVValueProvider
                    .LUSD3CRVValueProvider__constructor_InvalidPoolDecimals
                    .selector,
                address(curve3PoolMock)
            )
        );

        new LUSD3CRVValueProvider(
            // Oracle arguments
            // Time update window
            100,
            // Chainlink arguments
            address(curve3PoolMock),
            address(curve3PoolTokenMock),
            address(curveLUSD3CRVPoolMock),
            address(mockChainlinkLUSD),
            address(mockChainlinkUSDC),
            address(mockChainlinkDAI),
            address(mockChainlinkUSDT)
        );
    }

    function test_deploy_shouldRevertWithInvalidLUSDPoolDecimals() public {
        // Update the mock to return an unsupported decimal number
        curveLUSD3CRVPoolMock.givenQueryReturnResponse(
            abi.encodeWithSelector(ERC20.decimals.selector),
            MockProvider.ReturnData({success: true, data: abi.encode(1)}),
            false
        );

        // Set the expected error for the revert
        cheatCodes.expectRevert(
            abi.encodeWithSelector(
                LUSD3CRVValueProvider
                    .LUSD3CRVValueProvider__constructor_InvalidPoolDecimals
                    .selector,
                address(curveLUSD3CRVPoolMock)
            )
        );

        new LUSD3CRVValueProvider(
            // Oracle arguments
            // Time update window
            100,
            // Chainlink arguments
            address(curve3PoolMock),
            address(curve3PoolTokenMock),
            address(curveLUSD3CRVPoolMock),
            address(mockChainlinkLUSD),
            address(mockChainlinkUSDC),
            address(mockChainlinkDAI),
            address(mockChainlinkUSDT)
        );
    }
}
