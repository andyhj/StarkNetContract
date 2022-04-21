<?php
/**
 * Install `starknet.php`
 * composer require starknet-php/starknet.php
 * 
 * https://github.com/Starknet-php/starknet.php
 */

class StarkNetERC20
{
    private $key = "";  //account key

    private $contractAddress = "";  //contract address

    private $createAddress = "";   //Create a contract wallet address

    private $provider = null;

    private $signer = null;

    //日志驱动
    private $log_driver = 'contract/erc20';

    public function __construct()
    {        
        $work = "testnet";
        $this->provider = new Provider($work);
        $this->signer = new Signer($this->key, $work, $this->createAddress);
    }

    /**
     * transfer
     *
     * @param [type] $tokenId
     * @return void
     */
    public function transfer($recipient, $amount)
    {
        try {
            $response = $this->signer->addTransaction([
                'type' => 'INVOKE_FUNCTION',
                'contract_address' => $this->contractAddress,
                'entry_point_selector' => Stark::getSelectorFromName("transfer"),
                'calldata' => [$recipient, $amount * 10 ** 18, 0]
            ]);
            $hash = $response[0]['transaction_hash'];
            return $hash;
        } catch (\Throwable $th) {
            //error
        }
    }
    /**
     * allowance
     *  
     * @param [type] $owner  Authorizer
     * @param [type] $spender to whom
     * @return boolean
     */
    public function allowance($owner, $spender)
    {
        try {
            $response = $this->provider->callContract([
                'contract_address' => $this->contractAddress,
                'entry_point_selector' => Stark::getSelectorFromName('allowance'),
                'calldata' => Stark::compileCalldata(['owner' => $owner , 'spender' => $spender])
            ]);
            $number = Utils::hexToDec($response[0]);
            return $number;
        } catch (\Throwable $th) {
            //error
        }
    }
}
