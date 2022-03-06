// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {ElementFiValueProvider} from "src/oracle_implementations/discount_rate/ElementFi/ElementFiValueProvider.sol";

interface IFactoryElementFiValueProvider {
    function create(
        // Oracle parameters
        uint256 timeUpdateWindow_,
        uint256 maxValidTime_,
        int256 alpha_,
        //
        bytes32 poolId_,
        address balancerVaultAddress_,
        address poolToken_,
        address underlier_,
        address ePTokenBond_,
        int256 timeScale_,
        uint256 maturity_
    ) external returns (address);
}

contract FactoryElementFiValueProvider is IFactoryElementFiValueProvider {
    function create(
        // Oracle parameters
        uint256 timeUpdateWindow_,
        uint256 maxValidTime_,
        int256 alpha_,
        //
        bytes32 poolId_,
        address balancerVaultAddress_,
        address poolToken_,
        address underlier_,
        address ePTokenBond_,
        int256 timeScale_,
        uint256 maturity_
    ) external override(IFactoryElementFiValueProvider) returns (address) {
        ElementFiValueProvider elementFiValueProvider = new ElementFiValueProvider(
                timeUpdateWindow_,
                maxValidTime_,
                alpha_,
                poolId_,
                balancerVaultAddress_,
                poolToken_,
                underlier_,
                ePTokenBond_,
                timeScale_,
                maturity_
            );

        elementFiValueProvider.allowCaller(
            elementFiValueProvider.ANY_SIG(),
            msg.sender
        );
        return address(elementFiValueProvider);
    }
}
