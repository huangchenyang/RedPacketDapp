module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
	networks: {
        development: {
            host: "127.0.0.1",
            port: 18545,
            network_id: "*", // 匹配任何network id
			gas:2000000
         }
    }
};
