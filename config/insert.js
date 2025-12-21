/**
 * 远程调用格式示例：
 * https://raw.github.../insert_vless.js#inbound=vr-in.json
 * * 参数说明：
 * inbound: Sub-Store "Files" 中保存的 VLESS 入站配置文件名
 */

// 1. 从 URL 参数中获取文件名 ($arguments 由 Sub-Store 自动解析 URL # 后面的参数)
// 如果没传参数，默认使用 "vr-in.json"
const inboundFileName = $arguments.inbound || "vr-in.json";

// 2. 读取主配置 ($files[0] 是当前处理链的上游内容)
let config;
try {
  config = JSON.parse($files[0]);
} catch (e) {
  throw new Error("输入内容不是有效的 JSON，请检查源配置。");
}

// 3. 通过 produceArtifact 读取 Sub-Store 文件系统中的入站配置
// produceArtifact 是 Sub-Store 内部函数，即使脚本是远程的也能在本地环境执行
let customInboundRaw = await produceArtifact({
  type: "file",
  name: inboundFileName,
});

if (!customInboundRaw) {
  console.log(`⚠️ 未找到名为 "${inboundFileName}" 的文件，跳过插入。`);
} else {
  try {
    const customInbound = JSON.parse(customInboundRaw);

    // 4. 初始化 inbounds 数组
    if (!config.inbounds) {
      config.inbounds = [];
    }

    // 5. 插入到底部 (兼容对象或数组)
    if (Array.isArray(customInbound)) {
      config.inbounds.push(...customInbound);
    } else {
      config.inbounds.push(customInbound);
    }

    console.log(`✅ 成功将 "${inboundFileName}" 插入到 inbounds。`);

  } catch (e) {
    console.log(`❌ 解析入站文件失败: ${e.message}`);
  }
}

// 6. 返回修改后的配置
$content = JSON.stringify(config, null, 2);