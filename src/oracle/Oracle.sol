// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

import {Pausable} from "../pausable/Pausable.sol";

abstract contract Oracle is Pausable, IOracle {
    /// @notice Emitted when alpha value is invalid
    error Oracle__constructor_alphaInvalid(int256 alpha);

    /// @notice Emitted when a method is reentered
    error Oracle__nonReentrant();

    /// ======== Events ======== ///

    event ValueInvalid();
    event ValueUpdated(int256 currentValue, int256 nextValue);
    event OracleReset();

    /// ======== Storage ======== ///

    uint256 public immutable timeUpdateWindow;

    uint256 public immutable maxValidTime;

    uint256 public lastTimestamp;

    // alpha determines how much influence
    // the new value has on the computed moving average
    // A commonly used value is 2 / (N + 1)
    int256 public immutable alpha;

    // next EMA value
    int256 public nextValue;

    // current EMA value and its validity
    int256 private _currentValue;
    bool private _validReturnedValue;

    // reentrancy constants
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    // reentrancy guard flag
    uint256 private _reentrantGuard = _NOT_ENTERED;

    /// ======== Modifiers ======== ///

    modifier nonReentrant() {
        // Check if the guard is set
        if (_reentrantGuard != _NOT_ENTERED) {
            revert Oracle__nonReentrant();
        }

        // Set the guard
        _reentrantGuard = _ENTERED;

        // Allow execution
        _;

        // Reset the guard
        _reentrantGuard = _NOT_ENTERED;
    }

    constructor(
        uint256 timeUpdateWindow_,
        uint256 maxValidTime_,
        int256 alpha_
    ) {
        // Validate alpha
        if (alpha_ <= 0 || alpha_ > 1 * 10**18) {
            revert Oracle__constructor_alphaInvalid(alpha_);
        }

        timeUpdateWindow = timeUpdateWindow_;
        maxValidTime = maxValidTime_;
        alpha = alpha_;
        _validReturnedValue = false;
    }

    /// @notice Get the current value of the oracle
    /// @return the current value of the oracle
    /// @return whether the value is valid
    function value()
        public
        view
        override(IOracle)
        whenNotPaused
        returns (int256, bool)
    {
        // Value is considered valid if the value provider successfully returned a value
        // and it was updated before maxValidTime ago
        bool valid = _validReturnedValue &&
            (block.timestamp < lastTimestamp + maxValidTime);
        return (_currentValue, valid);
    }

    function getValue() external virtual returns (int256);

    function update()
        public
        override(IOracle)
        checkCaller
        nonReentrant
        returns (bool)
    {
        // Not enough time has passed since the last update
        if (lastTimestamp + timeUpdateWindow > block.timestamp) {
            // Exit early if no update is needed
            return false;
        }

        // Oracle update should not fail even if the value provider fails to return a value
        try this.getValue() returns (int256 returnedValue) {
            // Update the value using an exponential moving average
            if (_currentValue == 0) {
                // First update takes the current value
                nextValue = returnedValue;
                _currentValue = nextValue;
            } else {
                // Update the current value with the next value
                _currentValue = nextValue;

                // Update the EMA and store it in the next value
                int256 newValue = returnedValue;
                // EMA = EMA(prev) + alpha * (Value - EMA(prev))
                // Scales down because of fixed number of decimals
                nextValue =
                    _currentValue +
                    (alpha * (newValue - _currentValue)) /
                    10**18;
            }

            // Save when the value was last updated
            lastTimestamp = block.timestamp;
            _validReturnedValue = true;

            emit ValueUpdated(_currentValue, nextValue);

            return true;
        } catch {
            // When a value provider fails, we update the valid flag which will
            // invalidate the value instantly
            _validReturnedValue = false;
            emit ValueInvalid();
        }

        return false;
    }

    function pause() public checkCaller {
        _pause();
    }

    function unpause() public checkCaller {
        _unpause();
    }

    function reset() public whenPaused checkCaller {
        _currentValue = 0;
        nextValue = 0;
        lastTimestamp = 0;
        _validReturnedValue = false;

        emit OracleReset();
    }
}
