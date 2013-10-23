# 実装のためのパーツとなるメソッドです。
# それぞれ適切な位置で呼び出してください。


  # 変数初期化  by河野
  def initializeServers
    @server_totalNumber = 5  # サーバの総数。要設定
    @target_defserver = 0    # デフォルトの送り先となるサーバID
    @server_waiting_packet = Array.new(@server_totalNumber, 0)  # ACK待ちパケット数を記録
  end


  # 送信先を選ぶ処理  by河野
  # 返り値 : 送信先サーバのID。IPアドレスの末尾
  def selectServer
    i = @target_defserver
    while @server_waiting_packet[i] >= 5
      # 数値はACK待ちパケット数。要調整
      i = (i + 1) % @server_totalNumber
    end
    dest_server = i
    @server_waiting_packet[i] += 1
    # 復活判定
    if (i - @target_defserver + @server_totalNumber) % @server_totalNumber >= 2
      # 数値は連なったACK待ちサーバの数。要調整
      @server_waiting_packet[@target_defserver] = 0
      @target_defserver = (@target_defserver + 1) % @server_totalNumber
    end
    return dest_server
  end


  # サーバからACKを受け取った時の処理  by河野
  # 引数 : ACKを送信したサーバのID。IPアドレスの末尾
  def checkAck(server_id)
    @server_waiting_packet[server_id] -= 1   # 受信待ちACK数を1つ減らす
  end

