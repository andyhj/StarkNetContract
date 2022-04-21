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

## @title ERC721
## @description A minimalistic implementation of ERC721 Token Standard.
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
func Transfer(sender: felt, recipient: felt, token_id: Uint256):
end

@event
func Approval(owner: felt, approved: felt, token_id: Uint256):
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
func _owners(token_id: Uint256) -> (owner: felt):
end

@storage_var
func _balances(owner: felt) -> (balance: Uint256):
end

@storage_var
func _token_approvals(token_id: Uint256) -> (approved: felt):
end

@storage_var
func _is_approved_for_all(owner: felt, spender: felt) -> (approved: felt):
end

@storage_var
func _tokenPrice(caller: felt,tokenId:felt) -> (price: felt):
end

@storage_var
func _tokenid_belong(token_id: Uint256) -> (owner: felt):
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
    owner: felt
):
    _name.write(name)
    _symbol.write(symbol)
    _creator.write(owner)
    return()
end

#############################################
##              ERC721 LOGIC               ##
#############################################

@external
func approve{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
    range_check_ptr
}(
    spender: felt,
    tokenId: felt
):
    let token_id = Uint256(tokenId,0)
    let (caller) = get_caller_address()

    let (owner) = _owners.read(token_id)
    if caller == owner:
        tempvar caller_is_owner = 1
    else:
        tempvar caller_is_owner = 0
    end
    let (approved) = _is_approved_for_all.read(owner, caller)
    let (can_approve) = bitwise_or(caller_is_owner, approved)
    assert can_approve = 1

    _token_approvals.write(token_id, spender)

    ## Emit the approval event ##
    Approval.emit(caller, spender, token_id)

    return ()
end


@external
func mint{
        pedersen_ptr: HashBuiltin*, 
        syscall_ptr: felt*, 
        range_check_ptr
    }(to: felt, belong: felt, tokenId: felt):
    Ownable_only_owner()
    let token_id = Uint256(tokenId,0)
    with_attr error_message("ERC721: token_id is not a valid Uint256"):
        uint256_check(token_id)
    end
    with_attr error_message("ERC721: cannot mint to the zero address"):
        assert_not_zero(to)
    end
     # Ensures token_id is unique
    let (exists) = _exists(token_id)
    with_attr error_message("ERC721: token already minted"):
        assert exists = 0
    end

    if to == belong:
        _mint(to, token_id)
        return ()
    else:
        _tokenid_belong.write(token_id, belong)
        _mint(to, token_id)
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
    tokenId: felt
):
    let token_id = Uint256(tokenId,0)
    let (sender) = get_caller_address()
    let (owner) = _owners.read(token_id)
    assert sender = owner
    assert_not_zero(recipient)

    let (owner_balance) = _balances.read(sender)
    let (new_owner_balance: Uint256) = uint256_sub(owner_balance, Uint256(1,0))

    let (recipient_balance) = _balances.read(recipient)
    let (new_recipient_balance, _: Uint256) = uint256_add(recipient_balance, Uint256(1,0))

    _balances.write(sender, new_owner_balance)
    _balances.write(recipient, new_recipient_balance)

    _owners.write(token_id, recipient)

    _token_approvals.write(token_id, 0)

    ## Emit the transfer event ##
    Transfer.emit(sender, recipient, token_id)

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
    tokenId: felt
):
    let token_id = Uint256(tokenId,0)
    let (caller) = get_caller_address()
    let (owner) = _owners.read(token_id)

    assert sender = owner # wrong sender

    assert_not_zero(recipient)

    if caller == owner:
        tempvar caller_is_owner = 1
    else:
        tempvar caller_is_owner = 0
    end

    let (approved_spender) = _token_approvals.read(token_id)
    
    if approved_spender == caller:
        tempvar is_approved = 1
    else:
        tempvar is_approved = 0
    end

    let (is_approved_for_all) = _is_approved_for_all.read(owner, caller)
    let (can_transfer1) = bitwise_or(caller_is_owner, is_approved)
    let (can_transfer) = bitwise_or(can_transfer1, is_approved_for_all)
    assert can_transfer = 1

    let (owner_balance) = _balances.read(sender)
    let (new_owner_balance: Uint256) = uint256_sub(owner_balance, Uint256(1,0))

    let (recipient_balance) = _balances.read(recipient)
    let (new_recipient_balance, _: Uint256) = uint256_add(recipient_balance, Uint256(1,0))

    _balances.write(sender, new_owner_balance)
    _balances.write(recipient, new_recipient_balance)

    _owners.write(token_id, recipient)

    _token_approvals.write(token_id, 0)

    ## Emit the transfer event ##
    Transfer.emit(sender, recipient, token_id)

    return ()
end

#buy
@external
func buy{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(mytoken20: felt, _to: felt, tokenId: felt):
        alloc_locals
        let token_id = Uint256(tokenId,0)
        let (spender) = get_contract_address() #Get the current contract address
        let (sender) = get_caller_address() #Get the current logged in user
        let (owner) = _owners.read(token_id)

        let (exists) = _exists(token_id)
        with_attr error_message("ERC721: token id does not exist"):
            assert exists = 1
        end

        #Determine whether the token owner is the current contract
        with_attr error_message("ERC721: TokenID owners are not part of the contract"): 
            assert spender = owner
        end

        let (_price) = _tokenPrice.read(_to, tokenId) #Get tokenId price
        let (token_price) = uint256_le(Uint256(_price,0), Uint256(0,0))
        with_attr error_message("ERC721: TokenId does not set a price"):
            assert token_price = 0
        end
        
        let (atoAmount: Uint256) = ERC20Contract.allowance(mytoken20, sender, spender)  #Get the authorized amount of the current logged in user

        let (allowanc_price) = uint256_le(atoAmount, Uint256(_price*10**18,0))
        #Determine whether the authorized amount is greater than the tokenid amount
        with_attr error_message("ERC20: transfer amount exceeds allowanc"): 
            assert allowanc_price = 0
        end

        #Token transfer
        ERC20Contract.transferFrom(mytoken20, sender, _to, Uint256(_price*10**18,0))

        let (spender_balance) = _balances.read(spender)  #Get the number of contract tokenIDs
        let (new_spender_balance: Uint256) = uint256_sub(spender_balance, Uint256(1,0)) #Quantity minus one

        let (sender_balance) = _balances.read(sender)  #Get the number of tokenIDs of the current calling contract user
        let (new_sender_balance, _: Uint256) = uint256_add(sender_balance, Uint256(1,0)) #Quantity plus one

        _balances.write(spender, new_spender_balance)
        _balances.write(sender, new_sender_balance)

        _owners.write(token_id, sender)

        _token_approvals.write(token_id, 0)

        _tokenPrice.write(_to, tokenId, 0)

        ## Emit the transfer event ##
        Transfer.emit(spender, sender, token_id)
    return ()
end

#sell
@external
func sell{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(tokenId: felt, price: felt):
    alloc_locals
    let token_id = Uint256(tokenId,0)
    let _price = Uint256(price,0)
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address()
    let (owner) = _owners.read(token_id)

    #Determine whether the token owner is currently calling the contract user
    with_attr error_message("ERC721: The tokenID owner does not belong to you"): 
        assert sender = owner
    end

    let (token_price) = uint256_le(_price, Uint256(0,0))
    with_attr error_message("ERC721: TokenId does not set a price"):
        assert token_price = 0
    end
    
    transferFrom(sender, spender, tokenId)  #The token is transferred to the contract
    _tokenPrice.write(sender, tokenId, price)  #set price
    return ()
end

#revocation
@external
func revocation{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(tokenId: felt) :
    alloc_locals
    let token_id = Uint256(tokenId,0)
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address() #current contract caller
    let (owner) = _owners.read(token_id) #tokenid owner

    #Determine whether the token owner is the current contract
    with_attr error_message("ERC721: TokenID owners are not part of the contract"): 
        assert spender = owner
    end

    let (_price) = _tokenPrice.read(sender, tokenId) #Get tokenId price
    
    let (token_price) = uint256_le(Uint256(_price,0), Uint256(0,0))
    with_attr error_message("ERC721: TokenId does not set a price"):
        assert token_price = 0
    end

    let (spender_balance) = _balances.read(spender)  #Get the number of contract tokenIDs
    let (new_spender_balance: Uint256) = uint256_sub(spender_balance, Uint256(1,0)) #Quantity minus one

    let (sender_balance) = _balances.read(sender)  #Get the number of tokenIDs of the current calling contract user
    let (new_sender_balance, _: Uint256) = uint256_add(sender_balance, Uint256(1,0)) #Quantity plus one

    _balances.write(spender, new_spender_balance)
    _balances.write(sender, new_sender_balance)

    _owners.write(token_id, sender)

    _token_approvals.write(token_id, 0)

    _tokenPrice.write(sender, tokenId, 0)

    ## Emit the transfer event ##
    Transfer.emit(spender, sender, token_id)
    return ()
end

#Batch off-chain
@external
func batchTakeOut{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(froms: felt,tokenIds_len: felt, tokenIds: felt*) :
    if tokenIds_len == 0:
        return ()
    end
    alloc_locals
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address()

    with_attr error_message("ERC721: Not the current login account"): 
        assert sender = froms
    end
    
    batchTakeOut(froms=froms, tokenIds_len=tokenIds_len - 1, tokenIds=tokenIds + 1)

    let tokenId = Uint256([tokenIds],0)
    let (owner) = _owners.read(tokenId) #Get tokenID holder
    #Determine whether the token holder is currently calling the contract user
    with_attr error_message("ERC721: The tokenID owner does not belong to you"): 
        assert sender = owner
    end

    let (spender_balance) = _balances.read(spender)  #Get the number of contract tokenIDs
    let (new_spender_balance: Uint256, _: Uint256) = uint256_add(spender_balance, Uint256(1,0)) #Quantity plus one

    let (sender_balance) = _balances.read(sender)  #Get the number of tokenIDs of the current calling contract user
    let (new_sender_balance) = uint256_sub(sender_balance, Uint256(1,0)) #Quantity minus one

    _balances.write(spender, new_spender_balance)
    _balances.write(sender, new_sender_balance)

    _owners.write(tokenId, spender)

    _token_approvals.write(tokenId, 0)

    _tokenid_belong.write(tokenId, sender)

    ## Emit the transfer event ##
    Transfer.emit(sender, spender, tokenId)

    return ()
end

#batch on-chain
@external
func batchCochain{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    bitwise_ptr : BitwiseBuiltin*,
    range_check_ptr
}(froms: felt,tokenIds_len: felt, tokenIds: felt*) :
    if tokenIds_len == 0:
        return ()
    end
    alloc_locals
    let (spender) = get_contract_address() #Get the current contract address
    let (sender) = get_caller_address()

    with_attr error_message("ERC721: Not the current login account"): 
        assert sender = froms
    end
    batchCochain(froms=froms, tokenIds_len=tokenIds_len - 1, tokenIds=tokenIds + 1)

    let tokenId = Uint256([tokenIds],0)
    let (owner) = _owners.read(tokenId) #Get tokenID holder
    let (belong) = _tokenid_belong.read(tokenId) #Get the tokenID to which it belongs

    #Determine whether the token belongs to the current calling contract user
    with_attr error_message("ERC721: The tokenID owner does not belong to you"): 
        assert froms = belong
    end
    
    #Determine whether the token owner is the current contract
    with_attr error_message("ERC721: TokenID owners are not part of the contract"): 
        assert spender = owner
    end
    let (spender_balance) = _balances.read(spender)  #Get the number of contract tokenIDs
    let (new_spender_balance: Uint256) = uint256_sub(spender_balance, Uint256(1,0)) #Quantity minus one

    let (froms_balance) = _balances.read(froms)  #Get the number of tokenIDs of the current calling contract user
    let (new_froms_balance, _: Uint256) = uint256_add(froms_balance, Uint256(1,0)) #Quantity plus one

    _balances.write(spender, new_spender_balance)
    _balances.write(froms, new_froms_balance)

    _owners.write(tokenId, froms)

    _token_approvals.write(tokenId, 0)

    _tokenid_belong.write(tokenId, 0)

    ## Emit the transfer event ##
    Transfer.emit(spender, froms, tokenId)
    return ()
end

#############################################
##             INTERNAL LOGIC              ##
#############################################
func _exists{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(token_id: Uint256) -> (res: felt):
    let (res) = _owners.read(token_id)

    if res == 0:
        return (0)
    else:
        return (1)
    end
end

func _mint{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    recipient: felt,
    token_id: Uint256
):
    assert_not_zero(recipient) #invalid recipient
    let (token_owner) = _owners.read(token_id)
    assert token_owner = 0 #already minted

    let (current_balance) = _balances.read(owner=recipient)
    let (new_balance, _: Uint256) = uint256_add(current_balance, Uint256(1,0))
    _balances.write(recipient, new_balance)

    let (current_supply) = _total_supply.read()
    let (new_supply, _: Uint256) = uint256_add(current_supply, Uint256(1,0))
    _total_supply.write(new_supply)

    _owners.write(token_id, recipient)

    return ()
end

func _burn{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(
    token_id: Uint256
):
    let (owner) = _owners.read(token_id)
    assert_not_zero(owner) #not minted

    let (current_balance) = _balances.read(owner)
    let (new_balance: Uint256) = uint256_sub(current_balance, Uint256(1,0))
    _balances.write(owner, new_balance)

    let (current_supply) = _total_supply.read()
    let (new_supply: Uint256) = uint256_sub(current_supply, Uint256(1,0))
    _total_supply.write(new_supply)

    _owners.write(token_id, 0)
    _token_approvals.write(token_id, 0)

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
}(to: felt, tokenId: felt) -> (price: Uint256):
    let (res) = _tokenPrice.read(to, tokenId)
    return (Uint256(res,0))
end

@view
func getTokenidBelong{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(tokenId: felt) -> (res: felt):
    let token_id = Uint256(tokenId,0)
    let (res) = _tokenid_belong.read(token_id)
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
func ownerOf{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(tokenId: felt) -> (owner: felt):
    let token_id = Uint256(tokenId,0)
    let (owner) = _owners.read(token_id)
    return (owner)
end

@view
func balanceOf{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(owner: felt) -> (balance: Uint256):
    let (balance: Uint256) = _balances.read(owner)
    return (balance)
end

@view
func getApproved{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(tokenId: felt) -> (spender: felt):
    let token_id = Uint256(tokenId,0)
    let (spender) = _token_approvals.read(token_id)
    return (spender)
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
