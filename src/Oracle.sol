// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IValueProvider} from "./valueprovider/IValueProvider.sol";

contract Oracle {
    IValueProvider public immutable valueProvider;

    uint256 public immutable minTimeBetweenUpdates;

    uint256 public lastTimestamp;

    // alpha determines how much influence
    // the new value has on the computed moving average
    // A commonly used value is 2 / (N + 1)
    int256 public immutable alpha;

    // Exponential moving average
    int256 public ema;

    constructor(
        address valueProvider_,
        uint256 minTimeBetweenUpdates_,
        int256 alpha_
    ) {
        valueProvider = IValueProvider(valueProvider_);
        minTimeBetweenUpdates = minTimeBetweenUpdates_;
        alpha = alpha_;
    }

    /// @notice Get the current value of the oracle
    /// @return the current value of the oracle
    /// @return whether the value is stale (true) or fresh (false)
    function value() public view returns (int256, bool) {
        bool isStale = block.timestamp >= lastTimestamp + minTimeBetweenUpdates;
        return (ema, isStale);
    }

    function update() public {
        // Not enough time has passed since the last update
        if (lastTimestamp + minTimeBetweenUpdates > block.timestamp) {
            return;
        }

        // Update the value using an exponential moving average
        if (ema == 0) {
            // First update takes the current value
            ema = valueProvider.value();
        } else {
            // EMA = EMA(prev) + alpha * (Value - EMA(prev))
            // Scales down because of fixed number of decimals
            int256 emaPrevious = ema;
            int256 currentValue = valueProvider.value();
            ema = emaPrevious + (alpha * (currentValue - emaPrevious)) / 10**18;
        }

        // Save when the value was last updated
        lastTimestamp = block.timestamp;
    }
}
