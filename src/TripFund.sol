pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TripFund is Initializable {
    using SafeERC20 for IERC20;

    error ZeroToken();
    error ZeroOrganizer();
    error ZeroGoal();
    error InvalidDeadline();
    error ZeroAmount();
    error DeadlineReached();
    error DeadlineNotReached();
    error GoalNotReached();
    error GoalReached();
    error Unauthorized();
    error AlreadyWithdrawn();
    error NoContribution();

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    IERC20 public token;
    address public organizer;
    uint256 public goal;
    uint256 public deadline;
    mapping(address => uint256) public contributions;
    uint256 public totalRaised;
    bool public withdrawn;

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) external initializer {
        if (address(token_) == address(0)) revert ZeroToken();
        if (organizer_ == address(0)) revert ZeroOrganizer();
        if (goal_ == 0) revert ZeroGoal();
        if (deadline_ <= block.timestamp) revert InvalidDeadline();

        token = token_;
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function contribute(uint256 amount) external virtual {
        _acceptContribution(msg.sender, msg.sender, amount);
        emit Contributed(msg.sender, amount);
    }

    function withdraw() external {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised < goal) revert GoalNotReached();
        if (msg.sender != organizer) revert Unauthorized();
        if (withdrawn) revert AlreadyWithdrawn();

        uint256 amount = totalRaised;
        withdrawn = true;
        token.safeTransfer(organizer, amount);

        emit Withdrawn(organizer, amount);
    }

    function refund() external {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised >= goal) revert GoalReached();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContribution();

        contributions[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);

        emit Refunded(msg.sender, amount);
    }

    function _acceptContribution(address payer, address beneficiary, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= deadline) revert DeadlineReached();

        contributions[beneficiary] += amount;
        totalRaised += amount;
        token.safeTransferFrom(payer, address(this), amount);
    }
}
