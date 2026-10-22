pragma solidity 0.8.27;

import {TripFund} from "./TripFund.sol";

contract TripFundV2 is TripFund {
    error ZeroBeneficiary();

    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    function contributeFor(address beneficiary, uint256 amount) external {
        if (beneficiary == address(0)) revert ZeroBeneficiary();

        _acceptContribution(msg.sender, beneficiary, amount);
        emit ContributedFor(msg.sender, beneficiary, amount);
    }
}
