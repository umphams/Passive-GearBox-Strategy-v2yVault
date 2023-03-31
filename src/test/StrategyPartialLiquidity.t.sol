// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {Strategy} from "../Strategy.sol";
import {IVault} from "../interfaces/Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/console2.sol";

contract StrategyOperationsTest is StrategyFixture {
    // setup is run on before each test
    function setUp() public override {
        // setup vault
        super.setUp();
    }

    function testStrategyLimitedLiquidityNoLoss(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        for (uint8 i = 0; i < assetFixtures.length; ++i) {
            AssetFixture memory _assetFixture = assetFixtures[i];
            IVault vault = _assetFixture.vault;
            Strategy strategy = _assetFixture.strategy;
            IERC20 want = _assetFixture.want;
            uint8 _wantDecimals = ERC20(address(want)).decimals();
            string memory _wantSymbol = ERC20(address(want)).symbol();
            if (_wantDecimals != 18) {
                uint256 _decimalDifference = 18 - _wantDecimals;
                _amount = _amount / (10 ** _decimalDifference);
            }
            if (keccak256(abi.encodePacked(_wantSymbol)) == keccak256(abi.encodePacked("WETH"))) {
                _amount = _amount / 1_000;
            }
            deal(address(want), user, _amount);

            uint256 balanceBefore = want.balanceOf(address(user));
            vm.prank(user);
            want.approve(address(vault), _amount);
            vm.prank(user);
            vault.deposit(_amount);
            assertRelApproxEq(want.balanceOf(address(vault)), _amount, DELTA);

            skip(3 minutes);
            vm.prank(strategist);
            strategy.harvest();
            assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

            // @todo here we will simulate only 50% of liquidity (full withdraw not possible)

            vm.prank(strategist);
            strategy.tend();

            vm.prank(user);
            vault.withdraw();

            assertRelApproxEq(want.balanceOf(user), balanceBefore, DELTA);
        }
    }
}
