const StakeCapitalTemplate = artifacts.require("StakeCapitalTemplate")
const Token = artifacts.require("Token")
const Vault = artifacts.require("Vault")

// DAO Config Constants, modify if necessary
const STAKE_CAPITAL_DAO_ID = "stake-capital-test64" // This ID must be unique, change it for each new deployment or a revert will occur

const TEAM_VOTING_TOKEN_NAME = "Stake Capital Owners"
const TEAM_VOTING_TOKEN_SYMBOL = "SCO"
const TEAM_VOTING_PARAMS = ["500000000000000000", "300000000000000000", "86400"] // [supportRequired, minAcceptanceQuorum, voteDuration] 10^16 == 1%

const SCT_VOTING_TOKEN_NAME = "Wrapped Stake Capital Token"
const SCT_VOTING_TOKEN_SYMBOL = "wSCT"
const SCT_VOTING_PARAMS = ["500000000000000000", "300000000000000000", "3000"] // [supportRequired, minAcceptanceQuorum, voteDuration] 10^16 == 1%

const AGENT_APP_ID = "0x9ac98dc5f995bf0211ed589ef022719d1487e5cb2bab505676f0d084c07cf89a";
const ACCOUNTS_SCT_BALANCE = "50000000000000000000000" // 50000 SCT
const VAULT_DAI_BALANCE = "100000000000000000000000" // 100000 DAI
const VAULT_SCT_BALANCE = "100000000000000000000000" // 100000 DAI
const NETWORK_ARG = "--network"

const network = () => process.argv.includes(NETWORK_ARG) ? process.argv[process.argv.indexOf(NETWORK_ARG) + 1] : "local"

const stakeCapitalTemplateAddress = () => {
    if (network() === "rinkeby") {
        const Arapp = require("../arapp")
        return Arapp.environments.rinkeby.address
    } else {
        const Arapp = require("../arapp_local")
        return Arapp.environments.devnet.address
    }
}

module.exports = async () => {
    try {
        const creatorAccount = network() === "rinkeby"
            ? "0xdf456B614fE9FF1C7c0B380330Da29C96d40FB02"
            : "0xb4124ceb3451635dacedd11767f004d8a28c6ee7"

        const teamVotingMembers = [
            creatorAccount,
            "0xDCB72E4E80C7B432FeFAb9F77214e3BFc72AbFaa",
            "0xA7499Aa6464c078EeB940da2fc95C6aCd010c3Cc"
        ]
        const teamVotingMembersWeights = teamVotingMembers.map(account => "1000000000000000000") // 10^18 == 1

        console.log(`Creating SCT token...`)
        let sct = await Token.new(creatorAccount, "Stake Capital Token", "SCT")
        console.log(`SCT Token address: ${sct.address} \nTransferring SCT to ${teamVotingMembers[1]} and ${teamVotingMembers[2]}...`)
        await sct.transfer(teamVotingMembers[1], ACCOUNTS_SCT_BALANCE)
        await sct.transfer(teamVotingMembers[2], ACCOUNTS_SCT_BALANCE)
        console.log(`${creatorAccount} SCT balance: ${await sct.balanceOf(creatorAccount)} \n${teamVotingMembers[1]} SCT balance: ${await sct.balanceOf(teamVotingMembers[1])} \n${teamVotingMembers[2]} SCT balance: ${await sct.balanceOf(teamVotingMembers[2])}`)

        console.log(`\nCreating DAI token...`)
        let dai = await Token.new(creatorAccount, "Dai", "DAI")
        console.log(`DAI Token address: ${dai.address}`)

        let template = await StakeCapitalTemplate.at(stakeCapitalTemplateAddress())

        console.log(`\nCreate dao transaction 1...`)
        const prepareInstanceReceipt = await template.prepareInstance(
            TEAM_VOTING_TOKEN_NAME,
            TEAM_VOTING_TOKEN_SYMBOL,
            teamVotingMembers,
            teamVotingMembersWeights,
            TEAM_VOTING_PARAMS,
            SCT_VOTING_PARAMS,
            sct.address)

        console.log(`Transaction 1 mined. Gas used: ${prepareInstanceReceipt.receipt.gasUsed}`)
        // console.log(`wSCT Token Address: ${prepareInstanceReceipt.logs.filter(x => x.event === "DeployToken")[1].args.token}`)

        console.log(`\nCreate dao transaction 2...`)
        let newDaoReceipt = await template.newInstance(
            STAKE_CAPITAL_DAO_ID,
            dai.address,
            sct.address)

        console.log(`DAO address: ${prepareInstanceReceipt.logs.find(x => x.event === "DeployDao").args.dao} Gas used: ${newDaoReceipt.receipt.gasUsed}`)

        const vaultProxyAddress = newDaoReceipt.logs.find(x => x.event === "InstalledApp" && x.args.appId === AGENT_APP_ID).args.appProxy
        const vault = await Vault.at(vaultProxyAddress)

        console.log(`\nApprove and transfer SCT to Vault for use by Airdrop app....`)
        await sct.approve(vaultProxyAddress, VAULT_SCT_BALANCE)
        await vault.deposit(sct.address, VAULT_SCT_BALANCE)
        console.log(`Vault SCT balance: ${await sct.balanceOf(vault.address)}`)

        console.log(`\nApprove and transfer DAI to Vault for use by Rewards app....`)
        await dai.approve(vaultProxyAddress, VAULT_DAI_BALANCE)
        await vault.deposit(dai.address, VAULT_DAI_BALANCE)
        console.log(`Vault DAI balance: ${await dai.balanceOf(vault.address)}`)

    } catch (error) {
        console.log(error)
    }
    process.exit()
}