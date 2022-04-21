import { getStarknet } from '@argent/get-starknet'
import { hash } from 'starknet'
import utils from "./utils.js";

class Meta {
  static isConnected = false
  static activeAccount = null
  static activeSigner = null
  static activeProvider = null

  static isClickItemCochain = 0
  static isClickHeroCochain = 0
  static isClickItemXl = 0
  static isClickHeroXl = 0
  static isClickExchange = 0
  static isClickLogin = 0;

  // 1155
  static contractFAddress = ''

  // 721
  static contractSAddress = ''

  // 20
  static contractTAddress = ''

  /**
   * init
   */
  static async init(callback) {
    let starknet = getStarknet({ showModal: true })

    try {
      let [walletAddress] = await starknet.enable()

      console.log("isConnected:",starknet.isConnected);
      if (starknet.isConnected) {
        this.isConnected = true
        this.activeAccount = walletAddress
        this.activeSigner = starknet.signer
        this.activeProvider = starknet.provider
        starknet.on('accountsChanged', async ([account]) => {
          console.log("accountsChanged:",account);
          callback(account);
        })
      }
    } catch (e) {
      console.log("error:",e);
      return
    }
  }

  /**
   * Disconnect
   */
  static disconnnect() {
    this.isConnected = false
    this.activeAccount = null
    this.activeSigner = null
    this.activeProvider = null
  }

  /**
   * cochain
   * @param {*} authToken
   * @param {*} playerID
   * @param {*} tokenId
   * @param {*} number
   * @param {*} callback
   */
  static itemCochain(from, tokenId, number, callback) {
    this.activeSigner
        .addTransaction({
          type: 'INVOKE_FUNCTION',
          contract_address: this.contractFAddress,
          entry_point_selector: hash.getSelectorFromName('cochain'),
          calldata: [from, tokenId, number],
        })
        .then((response) =>{
          console.log("cochain",response);
          if (response.code == "TRANSACTION_RECEIVED") {
            var hash = response.transaction_hash
            callback(hash)
          }
        })
        .catch((error) =>{
          console.log(error)
        })
  }


  /**
   *Query the number of tokens
   * @param {*} authToken
   * @param {*} playerID
   * @param {*} address
   * @param {*} number
   * @param {*} callback
   */
  static balanceOf(address, callback) {
    //Query the number of tokens
    this.activeProvider.callContract({
        contractAddress: this.contractTAddress,
        entrypoint: 'balanceOf',
        calldata: [utils.toBN(address).toString()],
      })
      .then((balanceOfRes) => {
        console.log(55)
        var number = utils.toBN(balanceOfRes.result[0]).toString()
        callback(number)
      })
  }

}

window.meta = Meta
