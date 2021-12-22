// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Guarded} from "./Guarded.sol";
import {Pausable} from "./Pausable.sol";

import {Oracle} from "./Oracle.sol";

// @notice Emitted when trying to add an oracle that already exists
error AggregatorOracle__addOracle_oracleAlreadyRegistered(address oracle);

// @notice Emitted when trying to remove an oracle that does not exist
error AggregatorOracle__removeOracle_oracleNotRegistered(address oracle);

// @notice Emitted when one does not have the right permissions to manage _oracles
error AggregatorOracle__notAuthorized();

contract AggregatorOracle is Guarded, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // List of registered oracles
    EnumerableSet.AddressSet private _oracles;

    // Current aggregated value
    int256 private _aggregatedValue;

    /// @notice Returns the number of oracles
    function oracleCount() public view returns (uint256) {
        return _oracles.length();
    }

    /// @notice Adds an oracle to the list of oracles
    function oracleAdd(address oracle) public onlyRoot {
        bool added = _oracles.add(oracle);
        if (added == false) {
            revert AggregatorOracle__addOracle_oracleAlreadyRegistered(oracle);
        }
    }

    /// @notice Returns `true` if the oracle is registered
    function oracleExists(address oracle) public view returns (bool) {
        return _oracles.contains(oracle);
    }

    /// @notice Removes an oracle from the list of oracles
    function oracleRemove(address oracle) public onlyRoot {
        bool removed = _oracles.remove(oracle);
        if (removed == false) {
            revert AggregatorOracle__removeOracle_oracleNotRegistered(oracle);
        }
    }

    /// @notice Update values from oracles and return aggregated value
    function update() public {
        // Create of possible valid values
        uint256 oracleLength = _oracles.length();
        int256[] memory values = new int256[](oracleLength);

        // Count how many oracles have a valid value
        uint256 validValues = 0;

        // Update each oracle and get its value
        for (uint256 i = 0; i < oracleLength; i++) {
            Oracle oracle = Oracle(_oracles.at(i));

            try oracle.update() {
                try oracle.value() returns (int256 value, bool isValid) {
                    if (isValid) {
                        // Add the value to the list of valid values
                        values[validValues] = value;

                        // Increase count of valid values
                        validValues++;
                    }
                } catch {}
            } catch {}
        }

        // Aggregate the returned values
        _aggregatedValue = _aggregateValues(values, validValues);
    }

    /// @notice Returns the aggregated value
    function value() public view whenNotPaused returns (int256, bool) {
        return (_aggregatedValue, oracleCount() > 0);
    }

    /// @notice Aggregates the values
    function _aggregateValues(int256[] memory values, uint256 validValues)
        internal
        pure
        returns (int256)
    {
        // Avoid division by zero
        if (validValues == 0) {
            return 0;
        }

        int256 sum;
        for (uint256 i = 0; i < validValues; i++) {
            sum += values[i];
        }

        return sum / int256(validValues);
    }
}
