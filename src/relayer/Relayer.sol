// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRelayer} from "src/relayer/IRelayer.sol";
import {IOracle} from "src/oracle/IOracle.sol";
import {ICollybus} from "src/relayer/ICollybus.sol";
import {Guarded} from "src/guarded/Guarded.sol";

contract Relayer is Guarded, IRelayer {
    // @notice Emitted when trying to add an oracle that already exists
    error Relayer__addOracle_oracleAlreadyRegistered(
        address oracle,
        RelayerType relayerType
    );

    // @notice Emitted when trying to add an oracle for a tokenId that already has a registered oracle.
    error Relayer__addOracle_tokenIdHasOracleRegistered(
        address oracle,
        bytes32 tokenId,
        RelayerType relayerType
    );

    // @notice Emitter when trying to remove an oracle that was not registered.
    error Relayer__removeOracle_oracleNotRegistered(
        address oracle,
        RelayerType relayerType
    );

    // @notice Emitter when check() returns false
    error Relayer__executeWithRevert_checkFailed(RelayerType relayerType);

    struct OracleData {
        bool exists;
        bytes32 tokenId;
        int256 lastUpdateValue;
        uint256 minimumPercentageDeltaValue;
    }

    /// ======== Events ======== ///

    event OracleAdded(address oracleAddress);
    event OracleRemoved(address oracleAddress);
    event ShouldUpdate(bool shouldUpdate);
    event UpdateOracle(address oracle, int256 value, bool valid);
    event UpdatedCollybus(bytes32 tokenId, uint256 rate, RelayerType);

    /// ======== Storage ======== ///

    address public immutable collybus;

    RelayerType public immutable relayerType;

    // Mapping that will hold all the oracle params needed by the contract
    mapping(address => OracleData) private _oraclesData;

    // Mapping used tokenId's
    mapping(bytes32 => bool) public _encodedTokenIds;

    // Array used for iterating the oracles.
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _oracleList;

    constructor(address collybusAddress_, RelayerType type_) {
        collybus = collybusAddress_;
        relayerType = type_;
    }

    /// @notice Returns the number of registered oracles.
    /// @return the total number of oracles.
    function oracleCount() external view override(IRelayer) returns (uint256) {
        return _oracleList.length();
    }

    /// @notice         Returns the address of an oracle at index
    /// @dev            Reverts if the index is out of bounds
    /// @param index_   The internal index of the oracle
    /// @return         Returns the address pf the oracle
    function oracleAt(uint256 index_)
        external
        view
        override(IRelayer)
        returns (address)
    {
        return _oracleList.at(index_);
    }

    /// @notice         Checks whether an oracle is registered.
    /// @param oracle_  The address of the oracle.
    /// @return         Returns 'true' if the oracle is registered.
    function oracleExists(address oracle_)
        public
        view
        override(IRelayer)
        returns (bool)
    {
        return _oraclesData[oracle_].exists;
    }

    /// @notice                                 Registers an oracle to a token id and set the minimum threshold delta value
    ///                                         calculate the annual rate.
    /// @param oracle_                          The address of the oracle.
    /// @param encodedTokenId_                  The unique token id for which this oracle will update rate values.
    /// @param minimumPercentageDeltaValue_     The minimum value delta threshold needed in order to push values to the Collybus
    /// @dev                                    Reverts if the oracle is already registered or if the rate id is taken by another oracle.
    function oracleAdd(
        address oracle_,
        bytes32 encodedTokenId_,
        uint256 minimumPercentageDeltaValue_
    ) public override(IRelayer) checkCaller {
        // Make sure the oracle was not added previously
        if (oracleExists(oracle_)) {
            revert Relayer__addOracle_oracleAlreadyRegistered(
                oracle_,
                relayerType
            );
        }

        // Make sure there are no existing oracles registered for this rate Id
        if (_encodedTokenIds[encodedTokenId_]) {
            revert Relayer__addOracle_tokenIdHasOracleRegistered(
                oracle_,
                encodedTokenId_,
                relayerType
            );
        }

        // Add oracle in the oracle address array that is used for iterating.
        _oracleList.add(oracle_);

        // Mark the token Id as used
        _encodedTokenIds[encodedTokenId_] = true;

        // Update the oracle address => data mapping with the oracle parameters.
        _oraclesData[oracle_] = OracleData({
            exists: true,
            lastUpdateValue: 0,
            tokenId: encodedTokenId_,
            minimumPercentageDeltaValue: minimumPercentageDeltaValue_
        });

        emit OracleAdded(oracle_);
    }

    /// @notice         Unregisters an oracle.
    /// @param oracle_  The address of the oracle.
    /// @dev            Reverts if the oracle is not registered
    function oracleRemove(address oracle_)
        public
        override(IRelayer)
        checkCaller
    {
        // Make sure the oracle is registered
        if (!oracleExists(oracle_)) {
            revert Relayer__removeOracle_oracleNotRegistered(
                oracle_,
                relayerType
            );
        }

        // Reset the tokenId Mapping
        _encodedTokenIds[_oraclesData[oracle_].tokenId] = false;

        // Remove the oracle from the list
        // This returns true/false depending on if the oracle was removed
        _oracleList.remove(oracle_);

        // Reset struct to default values
        delete _oraclesData[oracle_];

        emit OracleRemoved(oracle_);
    }

    /// @notice Returns the oracle data for a given oracle address
    /// @param oracle_ The address of the oracle
    /// @return Returns the oracle data as `OracleData`
    function oraclesData(address oracle_)
        public
        view
        returns (OracleData memory)
    {
        return _oraclesData[oracle_];
    }

    /// @notice Iterates and updates each oracle until it finds one that should push data
    ///         in the Collybus, more exactly, the delta change in value is bigger than the minimum
    ///         threshold value set for that oracle.
    /// @dev    Oracles that return invalid values are skipped.
    /// @return Returns 'true' if at least one oracle should update data in the Collybus
    function check() public override(IRelayer) returns (bool) {
        uint256 arrayLength = _oracleList.length();
        for (uint256 i = 0; i < arrayLength; i++) {
            // Cache oracle address
            address localOracle = _oracleList.at(i);

            // Trigger the oracle to update its data
            IOracle(localOracle).update();

            (int256 rate, bool isValid) = IOracle(localOracle).value();

            emit UpdateOracle(localOracle, rate, isValid);
            if (!isValid) continue;

            if (
                checkDeviation(
                    _oraclesData[localOracle].lastUpdateValue,
                    rate,
                    _oraclesData[localOracle].minimumPercentageDeltaValue
                )
            ) {
                emit ShouldUpdate(true);
                return true;
            }
        }

        emit ShouldUpdate(false);
        return false;
    }

    /// @notice Iterates and updates all the oracles and pushes the updated data to Collybus for the
    ///         oracles that have delta changes in value bigger than the minimum threshold values.
    /// @dev    Oracles that return invalid values are skipped.
    function execute() public override(IRelayer) {
        // Update Collybus all tokenIds with the new discount rate
        uint256 arrayLength = _oracleList.length();
        for (uint256 i = 0; i < arrayLength; i++) {
            // Cache oracle address
            address localOracle = _oracleList.at(i);

            // We always update the oracles before retrieving the rates
            IOracle(localOracle).update();
            (int256 oracleValue, bool isValid) = IOracle(localOracle).value();

            if (!isValid) continue;

            OracleData storage oracleData = _oraclesData[localOracle];

            // If the change in delta rate from the last update is bigger than the threshold value push
            // the rates to Collybus
            if (
                checkDeviation(
                    oracleData.lastUpdateValue,
                    oracleValue,
                    oracleData.minimumPercentageDeltaValue
                )
            ) {
                oracleData.lastUpdateValue = oracleValue;

                if (relayerType == RelayerType.DiscountRate) {
                    ICollybus(collybus).updateDiscountRate(
                        uint256(oracleData.tokenId),
                        uint256(oracleValue)
                    );
                } else if (relayerType == RelayerType.SpotPrice) {
                    ICollybus(collybus).updateSpot(
                        address(uint160(uint256(oracleData.tokenId))),
                        uint256(oracleValue)
                    );
                }

                emit UpdatedCollybus(
                    oracleData.tokenId,
                    uint256(oracleValue),
                    relayerType
                );
            }
        }
    }

    /// @notice The function will call `execute()` if `check()` returns `true`, otherwise it will revert
    /// @dev This method is needed for services that try to updates the oracles on each block and only call the method if it doesn't fail
    function executeWithRevert() public override(IRelayer) {
        if (check()) {
            execute();
        } else {
            revert Relayer__executeWithRevert_checkFailed(relayerType);
        }
    }

    /// @notice             Returns true if the percentage difference between the two values is bigger than the `percentage`
    /// @param baseValue    The value that the percentage is based on
    /// @param newValue     The new value
    /// @param percentage   The percentage threshold value (100% = 100_00, 50% = 50_00, etc)
    function checkDeviation(
        int256 baseValue,
        int256 newValue,
        uint256 percentage
    ) public view returns (bool) {
        int256 deviation = (baseValue * int256(percentage)) / 100_00;

        if (
            baseValue + deviation <= newValue ||
            baseValue - deviation >= newValue
        ) return true;

        return false;
    }
}
