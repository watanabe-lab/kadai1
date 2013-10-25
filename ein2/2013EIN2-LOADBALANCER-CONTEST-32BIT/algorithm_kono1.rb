# 実装のためのパーツとなるメソッドです。
# 1. Controlleの実装クラス内でメソッドを定義
# 2. 初期化処理中に initializeServers を呼ぶ
# 3. 送信先サーバを選ぶ処理として selectNextServer を呼ぶ
# 4. 変数 @next_superserver に送信先サーバのID(IPアドレスの末尾,整数値)が入るのでそこへ送る
# 5. ACK受信処理で checkAck(server_id) を呼ぶ
#    server_id はACKを送ったサーバのID(IPアドレスの末尾,整数値)
# 関数の内部処理が変わっても、呼出し手順は変わらないと思います。
# 
# 

  # 変数初期化  by河野
  def initializeServers
    @server_totalNumber = 5  # サーバの総数。要設定
    @next_superserver = 0    # 次の送り先となるサーバID。IPアドレスの末尾
    @target_defserver = 0    # デフォルトの送り先となるサーバID
    @server_waiting_packet = Array.new(@server_totalNumber, 0)  # ACK待ちパケット数を記録
  end


  # 送信先を選ぶ処理  by河野
  # @next_superserver が更新されるので、パケット受信ごとに1回だけ実行する
  def selectNextServer
    i = @target_defserver
    while @server_waiting_packet[i] >= 5
      # 数値はACK待ちパケット数。要調整
      i = (i + 1) % @server_totalNumber
    end
    @next_superserver = i
    @server_waiting_packet[i] += 1
    # 復活判定
    if (i - @target_defserver + @server_totalNumber) % @server_totalNumber >= 2
      # 数値は連なったACK待ちサーバの数。要調整
      @server_waiting_packet[@target_defserver] = 0
      @target_defserver = (@target_defserver + 1) % @server_totalNumber
    end
  end


  # サーバからACKを受け取った時の処理  by河野
  # 引数 : ACKを送信したサーバのID。IPアドレスの末尾
  def checkAck(server_id)
    @server_waiting_packet[server_id] -= 1   # 受信待ちACK数を1つ減らす
  end

