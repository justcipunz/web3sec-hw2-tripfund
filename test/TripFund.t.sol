pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {RevertingToken} from "../src/mocks/RevertingToken.sol";

contract TripFundTest is Test {
    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    uint256 internal constant GOAL = 1_000 ether;
    uint256 internal constant INITIAL_BALANCE = 10_000 ether;

    MockToken internal token;
    TripFund internal implementation;
    TripFund internal fund;
    TransparentUpgradeableProxy internal proxy;

    address internal organizer;
    address internal proxyOwner;
    address internal alice;
    address internal bob;
    address internal outsider;
    uint256 internal deadline;

    function setUp() public {
        organizer = makeAddr("organizer");
        proxyOwner = makeAddr("proxyOwner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        outsider = makeAddr("outsider");
        deadline = block.timestamp + 7 days;

        token = new MockToken();
        implementation = new TripFund();
        (fund, proxy) = _deployFund(IERC20(address(token)), organizer, GOAL, deadline);
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
    }

    function testInitializationStoresParameters() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.totalRaised(), 0);
        assertFalse(fund.withdrawn());
    }

    function testInitializationRejectsZeroToken() public {
        bytes memory data = abi.encodeCall(TripFund.initialize, (IERC20(address(0)), organizer, GOAL, deadline));
        vm.expectRevert(TripFund.ZeroToken.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyOwner, data);
    }

    function testInitializationRejectsZeroOrganizer() public {
        bytes memory data = abi.encodeCall(TripFund.initialize, (IERC20(address(token)), address(0), GOAL, deadline));
        vm.expectRevert(TripFund.ZeroOrganizer.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyOwner, data);
    }

    function testInitializationRejectsZeroGoal() public {
        bytes memory data = abi.encodeCall(TripFund.initialize, (IERC20(address(token)), organizer, 0, deadline));
        vm.expectRevert(TripFund.ZeroGoal.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyOwner, data);
    }

    function testInitializationRejectsCurrentDeadline() public {
        bytes memory data =
            abi.encodeCall(TripFund.initialize, (IERC20(address(token)), organizer, GOAL, block.timestamp));
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyOwner, data);
    }

    function testInitializationRejectsPastDeadline() public {
        vm.warp(10);
        bytes memory data = abi.encodeCall(TripFund.initialize, (IERC20(address(token)), organizer, GOAL, 9));
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        new TransparentUpgradeableProxy(address(implementation), proxyOwner, data);
    }

    function testProxyRejectsRepeatedInitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        fund.initialize(IERC20(address(token)), organizer, GOAL, deadline);
    }

    function testImplementationRejectsDirectInitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(IERC20(address(token)), organizer, GOAL, deadline);
    }

    function testContributionsFromTwoParticipantsAndRepeatedContribution() public {
        _approveAndContribute(alice, 100 ether);
        _approveAndContribute(bob, 250 ether);
        _approveAndContribute(alice, 50 ether);

        assertEq(fund.contributions(alice), 150 ether);
        assertEq(fund.contributions(bob), 250 ether);
        assertEq(fund.totalRaised(), 400 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 150 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 250 ether);
        assertEq(token.balanceOf(address(proxy)), 400 ether);
    }

    function testContributeEmitsEvent() public {
        vm.startPrank(alice);
        token.approve(address(proxy), 100 ether);
        vm.expectEmit(true, false, false, true, address(proxy));
        emit Contributed(alice, 100 ether);
        fund.contribute(100 ether);
        vm.stopPrank();
    }

    function testContributeRejectsZeroWithoutChanges() public {
        uint256 aliceBalance = token.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(TripFund.ZeroAmount.selector);
        fund.contribute(0);

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testContributeRejectsInsufficientAllowanceWithoutChanges() public {
        uint256 aliceBalance = token.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert();
        fund.contribute(100 ether);

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testContributeRejectsInsufficientBalanceWithoutChanges() public {
        uint256 amount = INITIAL_BALANCE + 1;
        vm.prank(alice);
        token.approve(address(proxy), amount);

        vm.prank(alice);
        vm.expectRevert();
        fund.contribute(amount);

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(token.allowance(alice, address(proxy)), amount);
    }

    function testContributeTransferFromFailureRollsBackAccounting() public {
        RevertingToken revertingToken = new RevertingToken();
        (TripFund revertingFund, TransparentUpgradeableProxy revertingProxy) =
            _deployFund(IERC20(address(revertingToken)), organizer, GOAL, deadline);
        revertingToken.mint(alice, INITIAL_BALANCE);

        vm.prank(alice);
        revertingToken.approve(address(revertingProxy), 100 ether);
        revertingToken.setFailTransferFrom(true);

        vm.prank(alice);
        vm.expectRevert(RevertingToken.ForcedFailure.selector);
        revertingFund.contribute(100 ether);

        assertEq(revertingFund.contributions(alice), 0);
        assertEq(revertingFund.totalRaised(), 0);
        assertEq(revertingToken.balanceOf(alice), INITIAL_BALANCE);
        assertEq(revertingToken.balanceOf(address(revertingProxy)), 0);
    }

    function testAllowanceMustTargetProxy() public {
        vm.prank(alice);
        token.approve(address(implementation), 100 ether);

        vm.prank(alice);
        vm.expectRevert();
        fund.contribute(100 ether);

        assertEq(token.allowance(alice, address(implementation)), 100 ether);
        assertEq(token.allowance(alice, address(proxy)), 0);
        assertEq(fund.totalRaised(), 0);
    }

    function testContributionOneSecondBeforeDeadlineSucceeds() public {
        vm.warp(deadline - 1);
        _approveAndContribute(alice, 100 ether);
        assertEq(fund.contributions(alice), 100 ether);
    }

    function testContributionAtDeadlineReverts() public {
        vm.warp(deadline);
        vm.prank(alice);
        token.approve(address(proxy), 100 ether);
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlineReached.selector);
        fund.contribute(100 ether);
        assertEq(fund.totalRaised(), 0);
    }

    function testWithdrawBeforeDeadlineRevertsAfterGoalReached() public {
        _approveAndContribute(alice, GOAL);
        vm.prank(organizer);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.withdraw();
        assertFalse(fund.withdrawn());
    }

    function testRefundBeforeDeadlineRevertsBelowGoal() public {
        _approveAndContribute(alice, 100 ether);
        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.refund();
        assertEq(fund.contributions(alice), 100 ether);
    }

    function testOrganizerWithdrawsAtExactGoal() public {
        _approveAndContribute(alice, GOAL);
        vm.warp(deadline);

        uint256 organizerBalance = token.balanceOf(organizer);
        vm.prank(organizer);
        vm.expectEmit(true, false, false, true, address(proxy));
        emit Withdrawn(organizer, GOAL);
        fund.withdraw();

        assertTrue(fund.withdrawn());
        assertEq(fund.totalRaised(), GOAL);
        assertEq(token.balanceOf(organizer), organizerBalance + GOAL);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testOrganizerWithdrawsAllAccountingAboveGoal() public {
        uint256 raised = GOAL + 250 ether;
        _approveAndContribute(alice, raised);
        vm.warp(deadline);

        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), raised);
        assertEq(fund.totalRaised(), raised);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testOutsiderCannotWithdraw() public {
        _approveAndContribute(alice, GOAL);
        vm.warp(deadline);
        vm.prank(outsider);
        vm.expectRevert(TripFund.Unauthorized.selector);
        fund.withdraw();
        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(proxy)), GOAL);
    }

    function testRepeatedWithdrawReverts() public {
        _approveAndContribute(alice, GOAL);
        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();
        vm.prank(organizer);
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        fund.withdraw();
    }

    function testRefundAtSuccessfulOutcomeReverts() public {
        _approveAndContribute(alice, GOAL);
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();
        assertEq(fund.contributions(alice), GOAL);
    }

    function testWithdrawAtFailedOutcomeReverts() public {
        _approveAndContribute(alice, 100 ether);
        vm.warp(deadline);
        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();
        assertFalse(fund.withdrawn());
    }

    function testIndependentRefundsPreserveTotalRaised() public {
        uint256 aliceAmount = 100 ether;
        uint256 bobAmount = 200 ether;
        _approveAndContribute(alice, aliceAmount);
        _approveAndContribute(bob, bobAmount);
        vm.warp(deadline);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(proxy));
        emit Refunded(alice, aliceAmount);
        fund.refund();

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), bobAmount);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(proxy)), bobAmount);

        vm.prank(bob);
        fund.refund();

        assertEq(fund.contributions(bob), 0);
        assertEq(fund.totalRaised(), aliceAmount + bobAmount);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testRepeatedRefundReverts() public {
        _approveAndContribute(alice, 100 ether);
        vm.warp(deadline);
        vm.prank(alice);
        fund.refund();
        vm.prank(alice);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
    }

    function testRefundWithoutContributionReverts() public {
        vm.warp(deadline);
        vm.prank(outsider);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
    }

    function testDirectTransferDoesNotAffectAccounting() public {
        vm.prank(alice);
        assertTrue(token.transfer(address(proxy), 75 ether));
        assertEq(fund.totalRaised(), 0);
        assertEq(fund.contributions(alice), 0);
        assertEq(token.balanceOf(address(proxy)), 75 ether);
    }

    function testDirectTransferRemainsAfterSuccessfulWithdraw() public {
        uint256 surplus = 75 ether;
        _approveAndContribute(alice, GOAL);
        vm.prank(bob);
        assertTrue(token.transfer(address(proxy), surplus));
        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(address(proxy)), surplus);
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function testDirectTransferRemainsAfterAllRefunds() public {
        uint256 surplus = 75 ether;
        _approveAndContribute(alice, 100 ether);
        _approveAndContribute(bob, 200 ether);
        vm.prank(outsider);
        token.mint(outsider, surplus);
        vm.prank(outsider);
        assertTrue(token.transfer(address(proxy), surplus));
        vm.warp(deadline);
        vm.prank(alice);
        fund.refund();
        vm.prank(bob);
        fund.refund();
        assertEq(token.balanceOf(address(proxy)), surplus);
        assertEq(fund.totalRaised(), 300 ether);
    }

    function testWithdrawTransferFailureRollsBackMarker() public {
        RevertingToken revertingToken = new RevertingToken();
        (TripFund revertingFund, TransparentUpgradeableProxy revertingProxy) =
            _deployFund(IERC20(address(revertingToken)), organizer, GOAL, deadline);
        revertingToken.mint(alice, GOAL);
        vm.startPrank(alice);
        revertingToken.approve(address(revertingProxy), GOAL);
        revertingFund.contribute(GOAL);
        vm.stopPrank();
        vm.warp(deadline);
        revertingToken.setFailTransfer(true);

        vm.prank(organizer);
        vm.expectRevert(RevertingToken.ForcedFailure.selector);
        revertingFund.withdraw();

        assertFalse(revertingFund.withdrawn());
        assertEq(revertingFund.totalRaised(), GOAL);
        assertEq(revertingToken.balanceOf(address(revertingProxy)), GOAL);
    }

    function testRefundTransferFailureRollsBackContribution() public {
        RevertingToken revertingToken = new RevertingToken();
        (TripFund revertingFund, TransparentUpgradeableProxy revertingProxy) =
            _deployFund(IERC20(address(revertingToken)), organizer, GOAL, deadline);
        uint256 amount = 100 ether;
        revertingToken.mint(alice, amount);
        vm.startPrank(alice);
        revertingToken.approve(address(revertingProxy), amount);
        revertingFund.contribute(amount);
        vm.stopPrank();
        vm.warp(deadline);
        revertingToken.setFailTransfer(true);

        vm.prank(alice);
        vm.expectRevert(RevertingToken.ForcedFailure.selector);
        revertingFund.refund();

        assertEq(revertingFund.contributions(alice), amount);
        assertEq(revertingFund.totalRaised(), amount);
        assertEq(revertingToken.balanceOf(address(revertingProxy)), amount);
    }

    function _approveAndContribute(address contributor, uint256 amount) internal {
        vm.startPrank(contributor);
        token.approve(address(proxy), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function _deployFund(IERC20 asset, address organizer_, uint256 goal_, uint256 deadline_)
        internal
        returns (TripFund deployedFund, TransparentUpgradeableProxy deployedProxy)
    {
        bytes memory data = abi.encodeCall(TripFund.initialize, (asset, organizer_, goal_, deadline_));
        deployedProxy = new TransparentUpgradeableProxy(address(implementation), proxyOwner, data);
        deployedFund = TripFund(address(deployedProxy));
    }
}
