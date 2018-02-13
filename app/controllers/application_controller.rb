class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  def home
    @title = 'Home'
    @output = ApplicationController::namecoin_cli('getinfo')
    @output = JSON.parse(@output)
  
    @latest_blocks = Array.new
    blocks = @output["blocks"] - 6
    @output["blocks"].downto(blocks).each do |n|
      block = get_block(n)
      total_sent = 0
      block["tx"].each do |txid|
        transaction = get_transaction(txid)
        transaction["vout"].each do |vout|
          total_sent += vout["value"]
        end
      end
      block["total_sent"] = total_sent
      @latest_blocks << block
    end
    @latest_transactions = JSON.parse(ApplicationController::namecoin_cli('name_filter "^[i]?d/" 6'))
    @latest_transactions.each_with_index do |tx, index|
      @latest_transactions[index]["age"] = get_block(@latest_transactions[index]["height"])["time"]
      details = get_transaction(@latest_transactions[index]["txid"])
      details["vout"].each do |vout|
        if vout["scriptPubKey"] && vout["scriptPubKey"]["nameOp"] && vout["scriptPubKey"]["nameOp"]["name"] == @latest_transactions[index]["name"]
          @latest_transactions[index]["operation"] = vout["scriptPubKey"]["nameOp"]["op"]
          break
        end
      end
    end
    @latest_transactions = @latest_transactions.sort_by {|k| k["age"]}.reverse
  end

  def contact
    @title = 'Contact'
  end

  # Dynamic routes start here

  def search
    query = params[:query]    
    if query.downcase.start_with?('d/') || query.downcase.start_with?('id/')
      redirect_to "/name/#{query}"
    elsif query.length == 64
      redirect_to "/tx/#{query}"
    elsif query.count('g-zG-Z') > 0
      redirect_to "/address/#{query}"
    elsif query.count('a-fA-F') > 0
      redirect_to "/block/#{query}"
    elsif query.count('a-fA-F') == 0
      redirect_to "/block/#{query}"
    else
      redirect_to '/404'
    end
  end

  def block
    @title = "Block #{params[:block]}"
    @output = get_block(params[:block])

    @name_operations = Array.new
    txids = @output["tx"]
    txids.each do |txid|
      details = get_transaction(txid)
      details["vout"].each do |vout|
        if vout["scriptPubKey"] && vout["scriptPubKey"]["nameOp"] && vout["scriptPubKey"]["nameOp"]["name"]
          @name_operations << vout["scriptPubKey"]["nameOp"]
          @name_operations[-1]["txid"] = txid
        end
      end
    end

    @output["totals"] = {"output" => 0, "input" => 0}
    @output["tx"].each_with_index do |txid, index|
      @output["tx"][index] = get_transaction(txid, true, true)
      @output["totals"]["output"] += @output["tx"][index]["totals"]["output"]
      @output["totals"]["input"] += @output["tx"][index]["totals"]["input"]
    end
  end

  def transaction
    @title = "Transaction #{params[:transaction]}"
    @output = get_transaction(params[:transaction], true, true)
    @output["height"] = get_block(@output["blockhash"])["height"]
  end

  def address
    #Come back to this later.
    @title = "Address #{params[:address]}"
  end

  def name
    @title = "Name #{params[:name]}"
    params[:type] = params[:type].downcase
    params[:name] = params[:name].downcase
    if params[:type] == 'd'
      @output = JSON.parse(ApplicationController::namecoin_cli('name_show d/' + params[:name]))
      @history = JSON.parse(ApplicationController::namecoin_cli('name_history d/' + params[:name]))
    elsif params[:type] == 'id'
      @output = JSON.parse(ApplicationController::namecoin_cli('name_show id/' + params[:name]))
      @history = JSON.parse(ApplicationController::namecoin_cli('name_history id/' + params[:name]))
    end
    @history.each_with_index do |transaction, index|
      @history[index]["time"] = get_block(transaction["height"])["time"]
      details = get_transaction(transaction["txid"])
      details["vout"].each do |vout|
        if vout["scriptPubKey"] && vout["scriptPubKey"]["nameOp"] && vout["scriptPubKey"]["nameOp"]["name"]
          @history[index]["op"] = vout["scriptPubKey"]["nameOp"]["op"]
        end
      end
    end

    @history.reverse!
  end

  def self.namecoin_cli(command)
    x = "#{ENV['NAMECOIN_CLI']} -rpcuser=#{ENV['NAMECOIN_RPC_USER']} -rpcpassword=#{ENV['NAMECOIN_RPC_PASSWORD']} #{command} 2>&1"
    return `#{x}`
  end

  def get_transaction(txid, include_input_transactions = false, include_totals = false)
    output = JSON.parse(ApplicationController::namecoin_cli("getrawtransaction #{txid} 1"))
    if include_input_transactions
      output["vin"].each_with_index do |vin, index|
        if vin["txid"]
          output["vin"][index]["prevTransaction"] = get_transaction(vin["txid"])
        end
      end
      if include_totals
        output["totals"] = {"output" => 0, "input" => 0}
        output["vin"].each do |vin|
          if vin["prevTransaction"]
            output["totals"]["input"] += vin["prevTransaction"]["vout"][vin["vout"]]["value"]
          end
        end
        output["vout"].each_with_index do |vout, index|
          output["totals"]["output"] += vout["value"]
        end
      end      
    end
    return output
  end

  def get_block(block)
    if block.to_s.count('a-fA-F') > 0
      JSON.parse(ApplicationController::namecoin_cli('getblock ' + block))
    else
      JSON.parse(ApplicationController::namecoin_cli('getblock ' + ApplicationController::namecoin_cli('getblockhash ' + block.to_s)))
    end
  end
end
