%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import (
    call_contract, delegate_call, delegate_l1_handler, emit_event, get_block_number,
    get_block_timestamp, get_caller_address, get_contract_address, get_sequencer_address,
    get_tx_info, get_tx_signature, storage_read, storage_write)
from starkware.cairo.common.math import (
    abs_value, assert_250_bit, assert_in_range, assert_le, assert_le_felt, assert_lt,
    assert_lt_felt, assert_nn, assert_nn_le, assert_not_equal, assert_not_zero, sign,
    signed_div_rem
    )
from starkware.cairo.common.bitwise import bitwise_or
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_le, uint256_lt, uint256_check
)

#############################################
##            ERC20INTERFACE               ##
#############################################

@contract_interface
namespace ERC20Contract:
    func allowance(owner: felt, spender: felt) -> (remaining: Uint256):
    end

    func transferFrom(sender: felt, recipient: felt, amount: Uint256) -> (success: felt):
    end
end

## @title ERC1155
## @description A minimalistic implementation of ERC1155 Token Standard.
## @dev Uses the common uint256 type for compatibility with the base evm.
## @description Adapted from OpenZeppelin's Cairo Contracts: https://github.com/OpenZeppelin/cairo-contracts
## @author andreas <andreas@nascent.xyz> exp.table <github.com/exp-table>

#############################################
##                STRUCTS                  ##
#############################################

# in two parts because each felt can store a string of 31 bytes max
# an IPFS hash is 46 bytes long
struct baseURI:
    member prefix : felt
    member suffix : felt
end

struct tokenURI:
    member prefix : felt
    member suffix : felt
    member token_id : Uint256
end

#############################################
##                METADATA                 ##
#############################################

@storage_var
func _name() -> (name: felt):
end

@storage_var
func _symbol() -> (symbol: felt):
end

@storage_var
func _creator() -> (owner: felt):
end

func Ownable_only_owner{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }():
    let (owner) = _creator.read()
    let (caller) = get_caller_address()
    with_attr error_message("Ownable: caller is not the owner"):
        assert owner = caller
    end
    return ()
end

@view
func Ownable_get_owner{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (owner: felt):
    let (owner) = _creator.read()
    return (owner=owner)
end

#############################################
##                 EVENTS                  ##
#############################################

@event
func Transfer(sender: felt, recipient: felt, token_id: Uint256, number: Uint256):
end

@event
func Approval_For_All(owner: felt, operator: felt, approved: felt):
end

#############################################
##                 STORAGE                 ##
#############################################

@storage_var
func _base_uri() -> (base_uri: baseURI):
end

@storage_var
func _total_supply() -> (total_supply: Uint256):
end

@storage_var
func _balances(owner: felt,token_id: Uint256) -> (balance: Uint256):
end

@storage_var
func _is_approved_for_all(owner: felt, spender: felt) -> (approved: felt):
end

@storage_var
func _tokenPrice(caller: felt, tokenId: Uint256, number: Uint256, price: Uint256) -> (num: Uint256):
end

@storage_var
func _tokenid_belong(owner: felt, token_id: Uint256) -> (number: Uint256):
end
#############################################
##               CONSTRUCTOR               ##
#############################################

@constructor
func constructor{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    name: felt,
    symbol: felt,
    owner: felt,
):
    _name.write(name)
    _symbol.write(symbol)
    _creator.write(owner)
    return()
end

#############################################
##              ERC1155 LOGIC               ##
#############################################

@external
func mint{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(to: felt, belong: felt, tokenId: felt, number: felt):
    Ownable_only_owner()
    let token_id = Uint256(tokenId,0)
    let unit_number = Uint256(number,0)

    with_attr error_message("ERC1155: cannot mint to the zero address"):
        assert_not_zero(to)
    end

    if to == belong:
        _mint(to, token_id, unit_number)
        return ()
    else:
        _tokenid_belong.write(belong, token_id, unit_number)
        _mint(to, token_id, unit_number)
        return ()
    end
end

@external
func setApprovalForAll{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    operator: felt,
    approved: felt
):
    let (caller) = get_caller_address()
    _is_approved_for_all.write(caller, operator, approved)

    ## Emit the approval event ##
    Approval_For_All.emit(caller, operator, approved)

    return ()
end

@external
func transfer{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(
    recipient: felt,
    tokenId: felt,
    number: felt
):
    alloc_locals
    let token_id = Uint256(tokenId,0)
    let unit_number = Uint256(number,0)
    let (sender) = get_caller_address()
    assert_not_zero(recipient)

    let (owner_balance) = _balances.read(sender, token_id) #Get the number of existing tokens
    let (token_number) = uint256_lt(owner_balance, unit_number) #The amount is less than the transfer amount
    with_attr error_message("ERC1155: Insufficient token Quantity"):
        assert token_number = 0
    end
    let (new_owner_balance: Uint256) = uint256_sub(owner_balance, unit_number)

    let (recipient_balance) = _balances.read(recipient, token_id)
    let (new_recipient_balance, _: Uint256) = uint256_add(recipient_balance, unit_number)

    _balances.write(sender, token_id, new_owner_balance)
    _balances.write(recipient, token_id, new_recipient_balance)

    ## Emit the transfer event ##
    Transfer.emit(sender, recipient, token_id, unit_number)

    return ()
end

@external
func transferFrom{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(
    sender: felt,
    recipient: felt,
    tokenId: felt,
    number: felt
):
    let token_id = Uint256(tokenId,0)
    let unit_number = Uint256(number,0)
    let (caller) = get_caller_address()

    assert_not_zero(recipient)

    if caller == sender:
        tempvar caller_is_owner = 1
    else:
        tempvar caller_is_owner = 0
    end

    let (is_approved_for_all) = _is_approved_for_all.read(sender, caller)
    let (can_transfer) = bitwise_or(caller_is_owner, is_approved_for_all)
    assert can_transfer = 1

    let (owner_balance) = _balances.read(sender, token_id)
    let (new_owner_balance: Uint256) = uint256_sub(owner_balance, unit_number)

    let (recipient_balance) = _balances.read(recipient, token_id)
    let (new_recipient_balance, _: Uint256) = uint256_add(recipient_balance, unit_number)

    _balances.write(sender, token_id, new_owner_balance)
    _balances.write(recipient, token_id, new_recipient_balance)

    ## Emit the transfer event ##
    Transfer.emit(sender, recipient, token_id, unit_number)

    return ()
end

#buy
@external
func buy{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(mytoken20: felt, _to: felt, tokenId: felt, number: felt, price: felt):
        alloc_locals
        let token_id = Uint256(tokenId,0)
        let unit_number = Uint256(number,0)
        let unit_price = Uint256(price,0)
        let (spender) = get_contract_address() #Get the current contract address
        let (sender) = get_caller_address() #Get the current logged in user
        let (token_price) = uint256_le(unit_price, Uint256(0,0))
        with_attr error_message("ERC1155: TokenId does not set a price"):
            assert token_price = 0
        end

        let (_num) = _tokenPrice.read(_to, token_id, unit_number, unit_price) #Get the number of tokenIds
        let (token_num) = uint256_le(_num, Uint256(0,0))
        with_attr error_message("ERC1155: There is no number"):
            assert token_num = 0
        end
        
        let (atoAmount: Uint256) = ERC20Contract.allowance(mytoken20, sender, spender)  #Get the authorized amount of the current logged in user

        let (allowanc_price) = uint256_le(atoAmount, Uint256(price*10**18,0))
        #Determine whether the authorized amount is greater than the tokenid amount
        with_attr error_message("ERC20: transfer amount exceeds allowanc"): 
            assert allowanc_price = 0
        end

        #Token transfer
        ERC20Contract.transferFrom(mytoken20, sender, _to, Uint256(price*10**18,0))

        let (spender_balance) = _balances.read(spender, token_id)  #Get the number of contract tokenIDs
        let (new_spender_balance: Uint256) = uint256_sub(spender_balance, unit_number) #Quantity minus one

        let (sender_balance) = _balances.read(sender, token_id)  #Get the number of tokenIDs of the current calling contract user
        let (new_sender_balance, _: Uint256) = uint256_add(sender_balance, unit_number) #Quantity plus one

        _balances.write(spender, token_id, new_spender_balance)
        _balances.write(sender, token_id, new_sender_balance)

        let (new_token_num: Uint256) = uint256_sub(_num, Uint256(1,0)) #Quantity minus one

        _tokenPrice.write(_to, token_id, unit_number, unit_price, new_token_num)

        ## Emit the transfer event ##
        Transfer.emit(spender, sender, token_id, unit_number)
    return ()
end

#sell
@external
func sell{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(tokenId: felt, price: felt, number: felt):
    alloc_locals
    let token_id = Uint256(tokenId,0)
    let unit_number = Uint256(number,0)
    let _price = Uint256(price,0)
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address()

    let (spender_balance) = _balances.read(sender, token_id)  #Get the number of contract tokenIDs

    let (spender_balance_number) = uint256_lt(spender_balance, unit_number)
    with_attr error_message("ERC1155: Insufficient token Quantity"):
        assert spender_balance_number = 0
    end

    let (token_price) = uint256_le(_price, Uint256(0,0))
    with_attr error_message("ERC1155: TokenId does not set a price"):
        assert token_price = 0
    end
    
    transferFrom(sender, spender, tokenId, number)  #The token is transferred to the contract
    let (_num) = _tokenPrice.read(sender, token_id, unit_number, _price) #Get the number of tokenIds
    let (new_token_num, _: Uint256) = uint256_add(_num, Uint256(1,0)) #Quantity plus one
    _tokenPrice.write(sender, token_id, unit_number, _price, new_token_num)  #set price
    return ()
end

#revocation
@external
func revocation{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(tokenId: felt, number: felt, price: felt) :
    alloc_locals
    let token_id = Uint256(tokenId,0)
    let unit_number = Uint256(number,0)
    let _price = Uint256(price,0)
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address() #current contract caller

    let (_num) = _tokenPrice.read(sender, token_id, unit_number, _price) #Get tokenId price
    
    let (token_price) = uint256_le(_price, Uint256(0,0))
    with_attr error_message("ERC1155: TokenId does not set a price"):
        assert token_price = 0
    end

    let (spender_balance) = _balances.read(spender, token_id)  #Get the number of contract tokenIDs
    let (new_spender_balance: Uint256) = uint256_sub(spender_balance, unit_number) #number minus number

    let (sender_balance) = _balances.read(sender, token_id)  #Get the number of tokenIDs of the current calling contract user
    let (new_sender_balance, _: Uint256) = uint256_add(sender_balance, unit_number) #Quantity plus number

    _balances.write(spender, token_id, new_spender_balance)
    _balances.write(sender, token_id, new_sender_balance)

    let (new_token_num: Uint256) = uint256_sub(_num, Uint256(1,0)) #Quantity minus one

    _tokenPrice.write(sender, token_id, unit_number, _price, new_token_num)

    ## Emit the transfer event ##
    Transfer.emit(spender, sender, token_id, unit_number)
    return ()
end

#takeOut
@external
func takeOut{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(froms: felt, token_id: felt, number: felt) :
    alloc_locals
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address()

    with_attr error_message("ERC1155: Not the current login account"): 
        assert sender = froms
    end
    
    let tokenId = Uint256(token_id,0)
    let uintNumber = Uint256(number,0)

    let (sender_balance) = _balances.read(sender, tokenId)  #Get the number of tokenIDs of the current calling contract user
    let (spender_balance_number) = uint256_lt(sender_balance, uintNumber)
    with_attr error_message("ERC1155: Insufficient token Quantity"):
        assert spender_balance_number = 0
    end

    let (spender_balance) = _balances.read(spender, tokenId)  #Get the number of contract tokenIDs
    let (new_spender_balance: Uint256, _: Uint256) = uint256_add(spender_balance, uintNumber) #Quantity plus number

    let (new_sender_balance) = uint256_sub(sender_balance, uintNumber) #number minus number

    let (belong) = _tokenid_belong.read(froms, tokenId) #Get the number of tokenIDs
    let (new_belong_balance: Uint256, _: Uint256) = uint256_add(belong, uintNumber) #Quantity plus number

    _balances.write(spender, tokenId, new_spender_balance)
    _balances.write(sender, tokenId, new_sender_balance)

    _tokenid_belong.write(sender, tokenId, new_belong_balance)

    ## Emit the transfer event ##
    Transfer.emit(sender, spender, tokenId, uintNumber)

    return ()
end

#cochain
@external
func cochain{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(froms: felt, token_id: felt, number: felt) :
    alloc_locals
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address()

    let tokenId = Uint256(token_id,0)
    let uintNumber = Uint256(number,0)

    with_attr error_message("ERC1155: Not the current login account"): 
        assert sender = froms
    end

    let (belong) = _tokenid_belong.read(froms, tokenId) #Get the number of tokenIDs
    let (spender_balance_number) = uint256_lt(belong, uintNumber)

    with_attr error_message("ERC1155: Insufficient token Quantity"):
        assert spender_balance_number = 0
    end
    
    let (spender_balance) = _balances.read(spender, tokenId)  #Get the number of contract tokenIDs
    let (new_spender_balance: Uint256) = uint256_sub(spender_balance, uintNumber) #number minus number

    let (froms_balance) = _balances.read(froms, tokenId)  #Get the number of tokenIDs of the current calling contract user
    let (new_froms_balance, _: Uint256) = uint256_add(froms_balance, uintNumber) #Quantity plus number

    let (new_belong_balance: Uint256) = uint256_sub(belong, uintNumber) #number minus number

    _balances.write(spender, tokenId, new_spender_balance)
    _balances.write(froms, tokenId, new_froms_balance)

    _tokenid_belong.write(froms, tokenId, new_belong_balance)

    ## Emit the transfer event ##
    Transfer.emit(spender, froms, tokenId, uintNumber)
    return ()
end

@external
func updbelong{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(froms: felt, token_id: felt, number: felt) :
    Ownable_only_owner()
    let tokenId = Uint256(token_id,0)
    let uintNumber = Uint256(number,0)

    _tokenid_belong.write(froms, tokenId, uintNumber)
    return ()
end

#############################################
##             INTERNAL LOGIC              ##
#############################################
func _mint{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    recipient: felt,
    token_id: Uint256,
    number: Uint256
):
    assert_not_zero(recipient) #invalid recipient

    let (current_balance) = _balances.read(recipient, token_id)
    let (new_balance, _: Uint256) = uint256_add(current_balance, number)
    _balances.write(recipient, token_id, new_balance)

    let (current_supply) = _total_supply.read()
    let (new_supply, _: Uint256) = uint256_add(current_supply, number)
    _total_supply.write(new_supply)

    return ()
end


#############################################
##                ACCESSORS                ##
#############################################
@view
func getTokenSellPrice{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(to: felt, tokenId: felt, number: felt, price: Uint256) -> (num: Uint256):
    let token_id = Uint256(tokenId,0)
    let unit_number = Uint256(number,0)
    let (res) = _tokenPrice.read(to, token_id, unit_number, price)
    return (res)
end

@view
func getTokenidBelong{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(tokenId: felt) -> (res: Uint256):
    let token_id = Uint256(tokenId,0)
    let (sender) = get_caller_address()
    let (res) = _tokenid_belong.read(sender, token_id)
    return (res)
end

@view
func name{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (name: felt):
    let (name) = _name.read()
    return (name)
end

@view
func symbol{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (symbol: felt):
    let (symbol) = _symbol.read()
    return (symbol)
end

@view
func tokenUri{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(tokenId: felt) -> (token_uri: tokenURI):
    let token_id = Uint256(tokenId,0)
    let (base_uri : baseURI) = _base_uri.read()
    let token_uri = tokenURI(base_uri.prefix, base_uri.suffix, token_id)
    return (token_uri)
end

@view
func totalSupply{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() -> (total_supply: Uint256):
    let (total_supply: Uint256) = _total_supply.read()
    return (total_supply)
end

@view
func balanceOf{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(owner: felt, tokenId: felt) -> (balance: Uint256):
    let token_id = Uint256(tokenId,0)
    let (balance: Uint256) = _balances.read(owner, token_id)
    return (balance)
end

@view
func isApprovedForAll{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(owner: felt, operator: felt) -> (approved: felt):
    let (approved) = _is_approved_for_all.read(owner, operator)
    return (approved)
end
