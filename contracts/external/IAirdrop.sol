pragma solidity ^0.4.24;

import "@aragon/apps-agent/contracts/Agent.sol";
import "./ICycleManager.sol";

contract IAirdrop {

    bytes32 constant public START_ROLE = keccak256("START_ROLE");

    function initialize(Agent _agent, ICycleManager _cycleManager, address _sctAddress, bytes32 _root, string _dataURI) public;
}
