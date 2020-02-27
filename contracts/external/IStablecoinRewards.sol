pragma solidity ^0.4.24;

import "@aragon/apps-agent/contracts/Agent.sol";
import "./ITokenWrapper.sol";
import "./ICycleManager.sol";

contract IStablecoinRewards {

    bytes32 constant public CREATE_REWARD_ROLE = keccak256("CREATE_REWARD_ROLE");

    function initialize(ICycleManager _cycleManager, ITokenWrapper _wrappedSct, Agent _agent, ERC20 _stablecoin) public;
}
