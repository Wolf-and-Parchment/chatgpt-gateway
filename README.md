# chatgpt自建网关部署方案

## 写在前面
部署架构为1网关+N个负载节点组成，可根据自身GPT账号规模调整负载节点数量，建议GPT账号与代理节点，10:1，当然网关自身也可以是负载节点

所有节点均需自行准备机器，这里推荐一个VPS厂商，支持月付，购买美国节点即可，我自己集群也在用 [鼎力云VPS](https://www.dingliyun.cn/aff/QZYJIOYW)

注意：登录默认走xyhelper网关（获取session)，提供配置可桥接到付费接入点，感谢xy大佬~，**本网关不支持转API**


## 部署流程

### 安装网关

执行一键部署脚本

```
curl -sSfL -o proxy-node-quick-install.sh https://raw.githubusercontent.com/hanglegehang/chatgpt-proxy-node-deploy/main/proxy-node-quick-install.sh && bash proxy-node-quick-install.sh

```
##### 安装说明
AuthKey : 接口访问秘钥，对应share配置中的AuthKey，填写free为裸奔模式，忽略鉴权

Licence : 授权码，联系客服获取，需提供主节点IP

脚本安装成功后会打印网关地址，可以自行配置反代、https等，处理完成后修改share启动参数即可：

```
CHATPROXY: "http://部署节点机器IP:8100"

AUTHKEY: "你配置的值"
```
#### 配置项说明
配置文件目录`/opt/chatgpt-proxy-node/config.yaml`
```
# 代理节点地址，默认无代理  
PROXY_URL :
  - socks5://xx:yy@111.222.333.444:8443 
AUTH_KEY : 网关访问秘钥
LICENCE : 授权码，联系客服获取
AUTH_KEY_HEADER ：header中秘钥key名称，默认为AuthKey，非share网关可自行配置
XY_GATEWAY : xy付费用户桥接配置项，付费网关地址，默认为https://demo.xyhelper.cn，
XY_GATEWAY_AUTH_KEY : xy付费用户桥接配置项，付费网关key,默认为xyhelper
```

### 负载节点

执行一键部署脚本
```
curl -sSfL -o proxy-glider-quick-install.sh https://raw.githubusercontent.com/hanglegehang/chatgpt-proxy-glider-deploy/main/proxy-glider-quick-install.sh && bash proxy-glider-quick-install.sh
```
输入代理端口、账号、密码，如无特殊情况，一路回车即可

安装完成后会打印代理节点地址，复制留存

检查网关代理是否启动成功，`curl -x socks5://代理节点地址 myip.ipip.net`

编辑主节点机器 `/opt/chatgpt-proxy-node/config.yaml`，将代理地址填入配置文件，该文件热更新，无需重启容器，形如：
<img width="571" alt="image" src="https://github.com/hanglegehang/chatgpt-proxy/assets/20039029/4db55be5-fd24-40a7-9e0d-4a896ae91b74">




