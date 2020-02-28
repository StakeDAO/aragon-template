const StakeCapitalTemplate = artifacts.require("StakeCapitalTemplate")
const Token = artifacts.require("Token")
const Vault = artifacts.require("Vault")

// DAO Config Constants, modify if necessary
const STAKE_CAPITAL_DAO_ID = "stake-capital-test50" // This ID must be unique, change it for each new deployment or a revert will occur

const TEAM_VOTING_TOKEN_NAME = "Stake Capital Owners"
const TEAM_VOTING_TOKEN_SYMBOL = "SCO"
const TEAM_VOTING_MEMBERS_WEIGHTS = ["1000000000000000000"] // 10^18 == 1
const TEAM_VOTING_PARAMS = ["500000000000000000", "300000000000000000", "3000"] // [supportRequired, minAcceptanceQuorum, voteDuration] 10^16 == 1%

const SCT_VOTING_TOKEN_NAME = "Wrapped Stake Capital Token"
const SCT_VOTING_TOKEN_SYMBOL = "wSCT"
const SCT_VOTING_PARAMS = ["500000000000000000", "300000000000000000", "3000"] // [supportRequired, minAcceptanceQuorum, voteDuration] 10^16 == 1%

const AGENT_APP_ID = "0x9ac98dc5f995bf0211ed589ef022719d1487e5cb2bab505676f0d084c07cf89a";
const TEST_ACCOUNT_2_SCT_BALANCE = "5000000000000000000000" // 5000 SCT
const VAULT_DAI_BALANCE = "10000000000000000000000" // 10000 DAI
const NETWORK_ARG = "--network"

const stakeCapitalTemplateAddress = () => {
    if (process.argv.includes(NETWORK_ARG) && process.argv[process.argv.indexOf(NETWORK_ARG) + 1] === "rinkeby") {
        const Arapp = require("../arapp")
        return Arapp.environments.rinkeby.address
    } else {
        const Arapp = require("../arapp_local")
        return Arapp.environments.devnet.address
    }
}

module.exports = async () => {
    try {
        const [account1, account2] = web3.eth.accounts
        const TEAM_VOTING_MEMBERS = [account1]

        console.log(`Creating SCT token...`)
        let sct = await Token.new(account1, "Stake Capital Token", "SCT")
        console.log(`SCT Token address: ${sct.address} Transferring SCT to account2...`)
        await sct.transfer(account2, TEST_ACCOUNT_2_SCT_BALANCE)
        console.log(`Account1 SCT balance: ${await sct.balanceOf(account1)} Account2 SCT balance: ${await sct.balanceOf(account2)}`)

        console.log(`\nCreating DAI token...`)
        let dai = await Token.new(account1, "Dai", "DAI")
        console.log(`DAI Token address: ${dai.address}`)

        let template = await StakeCapitalTemplate.at(stakeCapitalTemplateAddress())

        console.log(`\nCreate dao transaction 1...`)
        const prepareInstanceReceipt = await template.prepareInstance(
            TEAM_VOTING_TOKEN_NAME,
            TEAM_VOTING_TOKEN_SYMBOL,
            TEAM_VOTING_MEMBERS,
            TEAM_VOTING_MEMBERS_WEIGHTS,
            TEAM_VOTING_PARAMS,
            SCT_VOTING_PARAMS,
            sct.address)

        console.log(`Voting tokens created. Gas used: ${prepareInstanceReceipt.receipt.gasUsed}`)
        // console.log(`wSCT Token Address: ${prepareInstanceReceipt.logs.filter(x => x.event === "DeployToken")[1].args.token}`)

        console.log(`\nCreate dao transaction 2...`)
        let newDaoReceipt = await template.newInstance(
            STAKE_CAPITAL_DAO_ID,
            dai.address)

        console.log(`DAO address: ${prepareInstanceReceipt.logs.find(x => x.event === "DeployDao").args.dao} Gas used: ${newDaoReceipt.receipt.gasUsed}`)

        const vaultProxyAddress = newDaoReceipt.logs.find(x => x.event === "InstalledApp" && x.args.appId === AGENT_APP_ID).args.appProxy
        const vault = await Vault.at(vaultProxyAddress)
        console.log(`\nApprove and transfer DAI to Vault for use by Rewards app....`)
        await dai.approve(vaultProxyAddress, VAULT_DAI_BALANCE)
        await vault.deposit(dai.address, VAULT_DAI_BALANCE)
        console.log(`Vault DAI balance: ${await dai.balanceOf(vault.address)}`)

    } catch (error) {
        console.log(error)
    }
    process.exit()
}