pragma solidity 0.4.24;

import "@aragon/templates-shared/contracts/TokenCache.sol";
import "@aragon/templates-shared/contracts/BaseTemplate.sol";
import "./external/ICycleManager.sol";
import "./external/ITokenWrapper.sol";
import "./external/IStablecoinRewards.sol";

// TODO: Update doc strings.
// TODO: Refactor _setupApps() function
contract StakeCapitalTemplate is BaseTemplate, TokenCache {

    string constant private ERROR_EMPTY_HOLDERS = "COMPANY_EMPTY_HOLDERS";
    string constant private ERROR_BAD_HOLDERS_STAKES_LEN = "COMPANY_BAD_HOLDERS_STAKES_LEN";
    string constant private ERROR_BAD_VOTE_SETTINGS = "COMPANY_BAD_VOTE_SETTINGS";
    string constant private ERROR_MISSING_TOKEN_CACHE = "TEMPLATE_MISSING_TOKEN_CACHE";

    address constant private ANY_ENTITY = address(-1);
    bool constant private TOKEN_TRANSFERABLE = true;
    uint8 constant private TOKEN_DECIMALS = uint8(18);
    uint256 constant private TOKEN_MAX_PER_ACCOUNT = uint256(0);

    struct DeployedContracts {
        Kernel dao;
        ITokenWrapper tokenWrapper;
        Voting stakerVoting;
        Voting teamVoting;
    }

    mapping (address => DeployedContracts) private deployedContracts;

    constructor(DAOFactory _daoFactory, ENS _ens, MiniMeTokenFactory _miniMeFactory, IFIFSResolvingRegistrar _aragonID)
        BaseTemplate(_daoFactory, _ens, _miniMeFactory, _aragonID) public
    {
        _ensureAragonIdIsValid(_aragonID);
        _ensureMiniMeFactoryIsValid(_miniMeFactory);
    }

    /**
    * @dev Prepare dao // TODO: Rename and fix docstring.
    * @param _teamTokenName String with the name for the token used by team member in the organization
    * @param _teamTokenSymbol String with the symbol for the token used by team members in the organization
    * @param _holders Array of token holder addresses
    * @param _stakes Array of token stakes for holders (token has 18 decimals, multiply token amount `* 10^18`)
    * @param _teamVotingSettings Array of [supportRequired, minAcceptanceQuorum, voteDuration] to set up the team voting app of the organization
    * @param _stakerVotingSettings Array of [supportRequired, minAcceptanceQuorum, voteDuration] to set up the staker voting app of the organization
    */
    function prepareInstance(string memory _teamTokenName, string memory _teamTokenSymbol, address[] memory _holders,
        uint256[] memory _stakes, uint64[3] memory _teamVotingSettings, uint64[3] memory _stakerVotingSettings, ERC20 _sctToken)
        public
    {
        _ensureCompanySettings(_holders, _stakes, _teamVotingSettings, _stakerVotingSettings);

        (Kernel dao, ACL acl) = _createDAO();

        MiniMeToken teamToken = _createToken(_teamTokenName, _teamTokenSymbol, TOKEN_DECIMALS);
        (Voting teamVoting, TokenManager tokenManager) = _setupApps(dao, acl, _holders, _stakes, _teamVotingSettings, teamToken);
        ITokenWrapper tokenWrapper = _setupTokenWrapper(dao, _sctToken, teamVoting);
        Voting stakerVoting = _setupStakerVoting(dao, tokenWrapper, _stakerVotingSettings);

        _createVotingPermissions(acl, stakerVoting, teamVoting, tokenManager, teamVoting);

        _storeContracts(dao, tokenWrapper, teamVoting, msg.sender);
    }

    /**
    * @dev Deploy a Company DAO using a previously cached MiniMe token
    * @param _id String with the name for org, will assign `[id].aragonid.eth`
    */
    function newInstance(string memory _id, ERC20 _stablecoin) public
    {
        _validateId(_id);

        (Kernel dao, ITokenWrapper tokenWrapper, Voting teamVoting) = _retrieveContracts(msg.sender);
        ACL acl = ACL(dao.acl());

        (Agent agent, Finance finance) = _setupAgentAndFinance(dao, acl, teamVoting);
        ICycleManager cycleManager = _setupCycleManager(dao);
        IStablecoinRewards stablecoinRewards = _setupStablecoinRewards(dao, acl, teamVoting, cycleManager, tokenWrapper, agent, _stablecoin);

        _setupAgentPermissions(acl, agent, finance, stablecoinRewards, teamVoting);
        _setupCycleManagerPermissions(acl, cycleManager, teamVoting, stablecoinRewards);
        _setupTokenWrapperPermissions(acl, tokenWrapper, stablecoinRewards, teamVoting);

        _transferRootPermissionsFromTemplateAndFinalizeDAO(dao, teamVoting);
        _registerID(_id, dao);
        _deleteStoredTokens(msg.sender);
    }

    function _setupTokenWrapper(Kernel _dao, ERC20 _sctToken, Voting _teamVoting) internal returns (ITokenWrapper) {
        bytes32 appId = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("token-wrapper-sc")));
        ITokenWrapper tokenWrapper = ITokenWrapper(_installNonDefaultApp(_dao, appId));
        tokenWrapper.initialize(_sctToken, "Wrapped SCT", "wSCT");
        return tokenWrapper;
    }

    function _setupStakerVoting(Kernel _dao, ITokenWrapper tokenWrapper, uint64[3] memory _stakerVotingSettings)
        internal returns (Voting)
    {
        bytes memory initializeData = abi.encodeWithSelector(Voting(0).initialize.selector, tokenWrapper,
            _stakerVotingSettings[0], _stakerVotingSettings[1], _stakerVotingSettings[2]);
        return Voting(_installNonDefaultApp(_dao, VOTING_APP_ID, initializeData));
    }

    function _setupAgentAndFinance(Kernel _dao, ACL _acl, Voting _teamVoting) internal returns (Agent, Finance) {
        Agent agent = _installDefaultAgentApp(_dao);
        Finance finance = _installFinanceApp(_dao, agent, uint64(1 days));
        _createFinanceCreatePaymentsPermission(_acl, finance, _teamVoting, _teamVoting);
        return (agent, finance);
    }

    function _setupCycleManager(Kernel _dao) internal returns (ICycleManager) {
        bytes32 _appId = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("cycle-manager")));
        bytes memory initializeData = abi.encodeWithSelector(ICycleManager(0).initialize.selector, 60);
        ICycleManager cycleManager = ICycleManager(_installDefaultApp(_dao, _appId, initializeData));

        return cycleManager;
    }

    function _setupStablecoinRewards(Kernel _dao, ACL _acl, Voting _teamVoting, ICycleManager _cycleManager,
        ITokenWrapper _tokenWrapper, Agent _agent, ERC20 _stablecoin) internal returns (IStablecoinRewards)
    {
        bytes32 _appId = keccak256(abi.encodePacked(apmNamehash("open"), keccak256("stablecoin-rewards")));
        bytes memory initializeData = abi.encodeWithSelector(IStablecoinRewards(0).initialize.selector, _cycleManager, _tokenWrapper, _agent, _stablecoin);
        IStablecoinRewards stablecoinRewards = IStablecoinRewards(_installNonDefaultApp(_dao, _appId));

        _acl.createPermission(ANY_ENTITY, stablecoinRewards, stablecoinRewards.CREATE_REWARD_ROLE(), _teamVoting);

        return stablecoinRewards;
    }

    function _setupAgentPermissions(ACL _acl, Agent _agent, Finance _finance, IStablecoinRewards _stablecoinRewards,
        Voting _teamVoting) internal
    {
        _acl.createPermission(_finance, _agent, _agent.TRANSFER_ROLE(), address(this));
        _acl.grantPermission(_stablecoinRewards, _agent, _agent.TRANSFER_ROLE());
        _acl.setPermissionManager(_teamVoting, _agent, _agent.TRANSFER_ROLE());
    }

    function _setupCycleManagerPermissions(ACL _acl, ICycleManager _cycleManager, Voting _teamVoting, IStablecoinRewards _stablecoinRewards) internal {
        _acl.createPermission(_teamVoting, _cycleManager, _cycleManager.UPDATE_CYCLE_ROLE(), _teamVoting);
        _acl.createPermission(_stablecoinRewards, _cycleManager, _cycleManager.START_CYCLE_ROLE(), _teamVoting);
    }

    function _setupTokenWrapperPermissions(ACL _acl, ITokenWrapper _tokenWrapper, IStablecoinRewards _stablecoinRewards, Voting _teamVoting) internal {
        _acl.createPermission(_stablecoinRewards, _tokenWrapper, _tokenWrapper.DEPOSIT_TO_ROLE(), _teamVoting);
        _acl.createPermission(_stablecoinRewards, _tokenWrapper, _tokenWrapper.WITHDRAW_FOR_ROLE(), _teamVoting);
    }

    function _setupApps(Kernel _dao, ACL _acl, address[] memory _holders, uint256[] memory _stakes,
        uint64[3] memory _teamVotingSettings, MiniMeToken teamToken) internal returns (Voting, TokenManager)
    {
        TokenManager tokenManager = _installTokenManagerApp(_dao, teamToken, TOKEN_TRANSFERABLE, TOKEN_MAX_PER_ACCOUNT);
        Voting teamVoting = _installVotingApp(_dao, teamToken, _teamVotingSettings);

        _mintTokens(_acl, tokenManager, _holders, _stakes);
        _setupPermissions(_acl, teamVoting, tokenManager);

        return (teamVoting, tokenManager);
    }

    function _setupPermissions(ACL _acl, Voting _teamVoting, TokenManager _tokenManager) internal {
        _createEvmScriptsRegistryPermissions(_acl, _teamVoting, _teamVoting);
        _createVotingPermissions(_acl, _teamVoting, _teamVoting, _tokenManager, _teamVoting);
        _createTokenManagerPermissions(_acl, _tokenManager, _teamVoting, _teamVoting);
        _acl.createPermission(_teamVoting, _tokenManager, _tokenManager.ASSIGN_ROLE(), _teamVoting);
    }

    function _ensureCompanySettings(address[] memory _holders, uint256[] memory _stakes,
        uint64[3] memory _teamVotingSettings, uint64[3] memory _stakerVotingSettings) private pure
    {
        require(_holders.length > 0, ERROR_EMPTY_HOLDERS);
        require(_holders.length == _stakes.length, ERROR_BAD_HOLDERS_STAKES_LEN);
        require(_teamVotingSettings.length == 3, ERROR_BAD_VOTE_SETTINGS);
        require(_stakerVotingSettings.length == 3, ERROR_BAD_VOTE_SETTINGS);
    }

    function _storeContracts(Kernel _dao, ITokenWrapper _tokenWrapper, Voting _teamVoting, address _deployer) internal {
        deployedContracts[_deployer].dao = _dao;
        deployedContracts[_deployer].tokenWrapper = _tokenWrapper;
        deployedContracts[_deployer].teamVoting = _teamVoting;
    }

    function _retrieveContracts(address _owner) internal returns (Kernel, ITokenWrapper, Voting) {
        require(deployedContracts[_owner].dao != address(0), ERROR_MISSING_TOKEN_CACHE);
        DeployedContracts memory ownerDeployedContracts = deployedContracts[_owner];
        return (
            ownerDeployedContracts.dao,
            ownerDeployedContracts.tokenWrapper,
            ownerDeployedContracts.teamVoting
        );
    }

    function _deleteStoredTokens(address _owner) internal {
        delete deployedContracts[_owner];
    }
}
