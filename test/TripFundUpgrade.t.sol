pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundV2} from "../src/TripFundV2.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract TripFundUpgradeTest is Test {
    event Contributed(address indexed contributor, uint256 amount);
    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    uint256 internal constant GOAL = 1_000 ether;
    uint256 internal constant INITIAL_BALANCE = 10_000 ether;

    MockToken internal token;
    TripFund internal implementationV1;
    TripFundV2 internal implementationV2;
    TransparentUpgradeableProxy internal proxy;
    ProxyAdmin internal proxyAdmin;
    TripFund internal fundV1;
    TripFundV2 internal fundV2;

    address internal organizer;
    address internal proxyOwner;
    address internal alice;
    address internal bob;
    address internal beneficiary;
    address internal outsider;
    uint256 internal deadline;

    function setUp() public {
        organizer = makeAddr("organizer");
        proxyOwner = makeAddr("proxyOwner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        beneficiary = makeAddr("beneficiary");
        outsider = makeAddr("outsider");
        deadline = block.timestamp + 7 days;

        token = new MockToken();
        implementationV1 = new TripFund();
        bytes memory data = abi.encodeCall(TripFund.initialize, (IERC20(address(token)), organizer, GOAL, deadline));
        proxy = new TransparentUpgradeableProxy(address(implementationV1), proxyOwner, data);
        fundV1 = TripFund(address(proxy));
        address adminAddress = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
        proxyAdmin = ProxyAdmin(adminAddress);

        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
    }

    function testProxyCreatedDedicatedAdminWithSeparateOwner() public view {
        assertTrue(address(proxyAdmin) != address(0));
        assertEq(proxyAdmin.owner(), proxyOwner);
        assertTrue(proxyOwner != organizer);
        assertTrue(address(proxyAdmin) != proxyOwner);
    }

    function testUpgradePreservesStateAndSupportsFailedOutcomeRefund() public {
        uint256 v1Amount = 100 ether;
        uint256 v2Amount = 50 ether;
        uint256 giftAmount = 75 ether;
        _approveAndContributeV1(alice, v1Amount);

        address proxyAddressBefore = address(proxy);
        uint256 proxyBalanceBefore = token.balanceOf(address(proxy));
        implementationV2 = new TripFundV2();
        _upgradeAsOwner();

        assertEq(address(proxy), proxyAddressBefore);
        assertEq(address(fundV2.token()), address(token));
        assertEq(fundV2.organizer(), organizer);
        assertEq(fundV2.goal(), GOAL);
        assertEq(fundV2.deadline(), deadline);
        assertEq(fundV2.contributions(alice), v1Amount);
        assertEq(fundV2.totalRaised(), v1Amount);
        assertFalse(fundV2.withdrawn());
        assertEq(token.balanceOf(address(proxy)), proxyBalanceBefore);

        vm.startPrank(bob);
        token.approve(address(proxy), v2Amount + giftAmount);
        fundV2.contribute(v2Amount);
        fundV2.contributeFor(beneficiary, giftAmount);
        vm.stopPrank();

        assertEq(fundV2.contributions(alice), v1Amount);
        assertEq(fundV2.contributions(bob), v2Amount);
        assertEq(fundV2.contributions(beneficiary), giftAmount);
        assertEq(fundV2.totalRaised(), v1Amount + v2Amount + giftAmount);
        assertEq(token.balanceOf(address(proxy)), v1Amount + v2Amount + giftAmount);

        uint256 beneficiaryBalance = token.balanceOf(beneficiary);
        vm.warp(deadline);
        vm.prank(beneficiary);
        fundV2.refund();

        assertEq(fundV2.contributions(beneficiary), 0);
        assertEq(token.balanceOf(beneficiary), beneficiaryBalance + giftAmount);
        assertEq(fundV2.totalRaised(), v1Amount + v2Amount + giftAmount);
    }

    function testOriginalContributeWorksAfterUpgrade() public {
        _deployAndUpgradeV2();
        vm.startPrank(alice);
        token.approve(address(proxy), 100 ether);
        vm.expectEmit(true, false, false, true, address(proxy));
        emit Contributed(alice, 100 ether);
        fundV2.contribute(100 ether);
        vm.stopPrank();
        assertEq(fundV2.contributions(alice), 100 ether);
        assertEq(fundV2.totalRaised(), 100 ether);
    }

    function testContributeForChargesPayerAndCreditsBeneficiary() public {
        _deployAndUpgradeV2();
        uint256 amount = 100 ether;
        uint256 payerBalance = token.balanceOf(alice);
        uint256 beneficiaryBalance = token.balanceOf(beneficiary);

        vm.startPrank(alice);
        token.approve(address(proxy), amount);
        vm.expectEmit(true, true, false, true, address(proxy));
        emit ContributedFor(alice, beneficiary, amount);
        fundV2.contributeFor(beneficiary, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), payerBalance - amount);
        assertEq(token.balanceOf(beneficiary), beneficiaryBalance);
        assertEq(fundV2.contributions(alice), 0);
        assertEq(fundV2.contributions(beneficiary), amount);
        assertEq(fundV2.totalRaised(), amount);
        assertEq(token.balanceOf(address(proxy)), amount);
    }

    function testContributeForAccumulatesOwnAndGiftedContributions() public {
        _deployAndUpgradeV2();
        token.mint(beneficiary, 100 ether);

        vm.startPrank(beneficiary);
        token.approve(address(proxy), 40 ether);
        fundV2.contribute(40 ether);
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(proxy), 60 ether);
        fundV2.contributeFor(beneficiary, 25 ether);
        fundV2.contributeFor(beneficiary, 35 ether);
        vm.stopPrank();

        assertEq(fundV2.contributions(beneficiary), 100 ether);
        assertEq(fundV2.totalRaised(), 100 ether);
    }

    function testContributeForRejectsZeroBeneficiary() public {
        _deployAndUpgradeV2();
        vm.prank(alice);
        vm.expectRevert(TripFundV2.ZeroBeneficiary.selector);
        fundV2.contributeFor(address(0), 100 ether);
        assertEq(fundV2.totalRaised(), 0);
    }

    function testContributeForRejectsZeroAmount() public {
        _deployAndUpgradeV2();
        vm.prank(alice);
        vm.expectRevert(TripFund.ZeroAmount.selector);
        fundV2.contributeFor(beneficiary, 0);
        assertEq(fundV2.totalRaised(), 0);
    }

    function testContributeForRejectsInsufficientAllowanceWithoutChanges() public {
        _deployAndUpgradeV2();
        uint256 aliceBalance = token.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert();
        fundV2.contributeFor(beneficiary, 100 ether);
        assertEq(fundV2.contributions(beneficiary), 0);
        assertEq(fundV2.totalRaised(), 0);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testContributeForRejectsInsufficientBalanceWithoutChanges() public {
        _deployAndUpgradeV2();
        uint256 amount = INITIAL_BALANCE + 1;
        vm.prank(alice);
        token.approve(address(proxy), amount);
        vm.prank(alice);
        vm.expectRevert();
        fundV2.contributeFor(beneficiary, amount);
        assertEq(fundV2.contributions(beneficiary), 0);
        assertEq(fundV2.totalRaised(), 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testContributeForRejectsAtDeadline() public {
        _deployAndUpgradeV2();
        vm.warp(deadline);
        vm.prank(alice);
        token.approve(address(proxy), 100 ether);
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlineReached.selector);
        fundV2.contributeFor(beneficiary, 100 ether);
        assertEq(fundV2.totalRaised(), 0);
    }

    function testOutsiderCannotUpgrade() public {
        implementationV2 = new TripFundV2();
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(implementationV2), bytes(""));
        assertEq(address(fundV1.token()), address(token));
    }

    function testOrganizerCannotUpgradeWithoutProxyOwnership() public {
        implementationV2 = new TripFundV2();
        vm.prank(organizer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, organizer));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(implementationV2), bytes(""));
    }

    function testProxyRejectsInitializationAfterUpgrade() public {
        _deployAndUpgradeV2();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        fundV2.initialize(IERC20(address(token)), organizer, GOAL, deadline);
    }

    function testV2ImplementationRejectsDirectInitialization() public {
        implementationV2 = new TripFundV2();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementationV2.initialize(IERC20(address(token)), organizer, GOAL, deadline);
    }

    function testUpgradeOccursBeforeDeadline() public {
        vm.warp(deadline - 1);
        _deployAndUpgradeV2();
        assertEq(address(fundV2.token()), address(token));
        assertLt(block.timestamp, fundV2.deadline());
    }

    function _approveAndContributeV1(address contributor, uint256 amount) internal {
        vm.startPrank(contributor);
        token.approve(address(proxy), amount);
        fundV1.contribute(amount);
        vm.stopPrank();
    }

    function _deployAndUpgradeV2() internal {
        implementationV2 = new TripFundV2();
        _upgradeAsOwner();
    }

    function _upgradeAsOwner() internal {
        vm.prank(proxyOwner);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(proxy)), address(implementationV2), bytes(""));
        fundV2 = TripFundV2(address(proxy));
    }
}
