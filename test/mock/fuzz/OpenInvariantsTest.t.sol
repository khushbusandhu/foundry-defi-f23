//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(dsce));
    }

    function invariant_protocolMustHaveMoreValueThanSupply() external view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalwethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        uint256 wethvalue = dsce.getUsdValue(weth, totalwethDeposited);
        uint256 wbtcvalue = dsce.getUsdValue(wbtc, totalBtcDeposited);
        assert(wethvalue + wbtcvalue >= totalSupply);
    }
}
