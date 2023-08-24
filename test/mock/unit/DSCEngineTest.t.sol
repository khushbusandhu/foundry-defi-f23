//SPDX-License-identifier:MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mock/ MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address wethPriceFeed;
    address wbtcPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethPriceFeed, wbtcPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    address[] public tokenAddressess;
    address[] public priceFeedAddressess;

    function testRevertsIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddressess.push(weth);
        priceFeedAddressess.push(wethPriceFeed);
        priceFeedAddressess.push(wbtcPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddressess,priceFeedAddressess,address(dsc));
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(USER, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositeCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN","RAN",USER,AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositeCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateral(weth, AMOUNT_COLLATERAL);
        _;
    }

    function testCanDepositeCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedDscMinted = 0;
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }

    function testCanDepositeCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHave() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.burnDsc(1);
    }

    modifier DepositeCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanBurnDsc() public DepositeCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.burnDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testProperlyReportedHealthFactor() public DepositeCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 actualHealthFactor = dsce.getHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public DepositeCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(wethPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        assert(userHealthFactor == 0.9 ether);
    }

    function testCantLiquidateGoodHealthFactor() public DepositeCollateralAndMintedDsc {
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_TO_MINT);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
    }
}
