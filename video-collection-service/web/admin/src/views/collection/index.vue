<template>
  <div class="collection-studio">
    <header class="studio-header">
      <div><span class="eyebrow">BLLII-FAMILIAR STUDIO</span><h1>使魔规则工坊</h1><p>全网番剧与内容感知，一套规则，精准入库。</p></div>
      <div class="actions">
        <r-button @click="$router.push('/scheduler')"><r-icon><Activity /></r-icon>使魔调度</r-button>
        <r-dropdown trigger="click" @command="handleCollectAll">
          <r-button type="warning">
            <r-icon><Refresh /></r-icon>一键唤醒采集<r-icon class="r-icon--right"><ArrowDown /></r-icon>
          </r-button>
          <template #dropdown>
            <r-dropdown-menu>
              <r-dropdown-item :command="24">近 24 小时增量同步</r-dropdown-item>
              <r-dropdown-item :command="0" divided style="color: #e6a23c;">全量历史补全</r-dropdown-item>
            </r-dropdown-menu>
          </template>
        </r-dropdown>
        <r-dropdown trigger="click" @command="applyPreset">
          <r-button type="success">
            <r-icon><Zap /></r-icon>载入预设规则<r-icon class="r-icon--right"><ArrowDown /></r-icon>
          </r-button>
          <template #dropdown>
            <r-dropdown-menu>
              <r-dropdown-item command="standard_video">🎬 标准影视 JSON 采集 (自动分集)</r-dropdown-item>
              <r-dropdown-item command="agihunt_ai_news" divided>⚡ AGI Hunt · AI 实时快讯 / 日报</r-dropdown-item>
              <r-dropdown-item command="tmdb_movie" divided>🎬 TMDB · 热门影视作品全量</r-dropdown-item>
              <r-dropdown-item command="tmdb_popular_person">👤 TMDB · 热门影人与演职员档案库</r-dropdown-item>
              <r-dropdown-item command="tmdb_search_person">🔍 TMDB · 演员名称精准检索</r-dropdown-item>
            </r-dropdown-menu>
          </template>
        </r-dropdown>
        <r-button type="primary" @click="createRule('api')">新建使魔规则</r-button>
      </div>
    </header>
    <div class="studio-layout">
      <aside class="rule-library">
        <div class="library-title"><strong>我的规则</strong><r-button text :loading="loading" @click="loadRules">刷新</r-button></div>
        <r-input v-model="search" placeholder="搜索规则名称" clearable />
        <r-empty v-if="!filteredRules.length" description="从右侧模板开始配置" :image-size="70" />
        <button v-for="rule in filteredRules" :key="rule.id" class="rule-item" :class="{ selected: form.id === rule.id }" @click="editRule(rule)">
          <span>{{ rule.name }}</span><small>{{ inputLabel(rule.filter.pipeline.input) }} · {{ targetLabel(rule.filter.pipeline.target) }}</small>
          <small :class="{ enabled: rule.enabled }">{{ rule.enabled ? '已加入自动调度' : '仅手动运行' }}</small>
        </button>
        <r-divider /><p class="helper">统一采集工坊：覆盖标准影视 JSON/XML 接口、网页爬虫、外部数据库与文件导入，内置多集自动切分与数据校正。</p>
      </aside>
      <main class="workspace">
        <div class="editor-heading">
          <div>
            <h2>{{ form.name || '未命名使魔规则' }}</h2>
            <span class="helper">{{ isSaved ? '已保存规则' : '新规则' }} · {{ dirty ? '有未保存修改' : '配置已同步' }}</span>
          </div>
          <div class="actions">
            <r-button :disabled="!isSaved" @click="openRuleLogs">
              <r-icon><Refresh :class="{ 'rotating-icon': isRuleRunning }" /></r-icon>进程与日志
            </r-button>
            <r-button :disabled="!isSaved" @click="cloneRule">复制</r-button>
            <r-button :disabled="!isSaved" @click="showRecords">查看结果</r-button>
            <r-button :disabled="!isSaved" type="danger" plain @click="removeRule">删除</r-button>
          </div>
        </div>
        <r-steps :active="step" finish-status="success" simple class="steps"><r-step title="选择来源" /><r-step title="连接与提取" /><r-step title="映射与清洗" /><r-step title="预览与运行" /></r-steps>

        <section v-show="step === 0">
          <h3>数据从哪里来？</h3><p class="helper">来源与内容类型独立配置。先选来源，再决定保存为什么内容。</p>
          <r-alert v-if="isWebhookForm" title="这是 Webhook 推送源（非主动拉取流水线）。选择业务类型后保存；默认文章。密钥与开关在「使魔节点管理」配置。" type="warning" :closable="false" show-icon class="mb-alert" />
          <div class="source-cards">
            <button
              v-if="isWebhookForm"
              class="chosen"
              type="button"
              disabled
            ><span>📥</span><strong>Webhook 推送</strong><small>外部 POST · 按业务类型入库</small></button>
            <button
              v-for="item in sourceOptions"
              v-show="!isWebhookForm"
              :key="item.value"
              :class="{ chosen: pipeline.input === item.value }"
              @click="pipeline.input = item.value"
            ><span>{{ item.icon }}</span><strong>{{ item.label }}</strong><small>{{ item.description }}</small></button>
          </div>
          <r-form label-position="top" class="basics">
            <r-form-item label="规则名称"><r-input v-model="form.name" placeholder="例如：产品资讯 / 旧站文章迁移" maxlength="100" :disabled="isWebhookForm" /></r-form-item>
            <r-form-item label="内容类型">
              <r-select v-model="pipeline.target" style="min-width: 220px">
                <r-option v-for="type in businessTypes" :key="type.slug" :label="type.name" :value="type.slug" />
              </r-select>
            </r-form-item>
          </r-form>
          <r-alert :title="targetHint" type="info" :closable="false" show-icon />
        </section>

        <section v-show="step === 1">
          <h3>{{ inputLabel(pipeline.input) }}配置</h3>
          <r-form label-position="top">
            <template v-if="pipeline.input === 'webhook' || isWebhookForm">
              <r-alert title="推送地址：POST /api/webhooks/collector（需 HMAC 签名）。接收后按所选业务类型入库；下方展示服务端标准字段映射。" type="info" :closable="false" />
              <r-form-item label="源标识 / API">
                <r-input :model-value="form.api" disabled />
              </r-form-item>
              <p class="helper">密钥、过期时间与启用状态请到「使魔节点管理」编辑本 Webhook 源。工坊可选择并保存业务类型，查看采集结果。</p>
            </template>
            <template v-else-if="pipeline.input === 'api' || pipeline.input === 'rss' || pipeline.input === 'html'">
              <r-form-item :label="pipeline.input === 'rss' ? 'Feed 订阅地址 (RSS / Atom)' : pipeline.input === 'api' ? '请求地址' : '列表页地址'">
                <r-input v-model="form.api" :placeholder="pipeline.input === 'rss' ? 'https://agihunt.info/feed.xml' : 'https://example.com/articles'" />
              </r-form-item>
              <template v-if="pipeline.input === 'rss'">
                <r-alert title="标准 RSS 2.0 / Atom 1.0 资讯源：自动解析 title、description/content、summary、link、author/creator、pub_date 及封面图；已支持 AGI Hunt、各大媒体及前沿技术博客订阅。" :closable="false" type="info" />
              </template>
              <template v-else-if="pipeline.input === 'api'">
                <div class="form-grid"><r-form-item label="请求方式"><r-select v-model="pipeline.request.method"><r-option label="GET" value="GET" /><r-option label="POST" value="POST" /></r-select></r-form-item><r-form-item label="列表在 JSON 中的路径"><r-input v-model="pipeline.request.list_path" placeholder="data.items；根数组填写 $" /></r-form-item></div>
                <r-form-item v-if="pipeline.request.method === 'POST'" label="请求体"><r-input v-model="pipeline.request.body" type="textarea" :rows="4" placeholder='{"category": "news"}' /></r-form-item>
              </template>
              <template v-else>
                <r-alert title="静态 HTML 采集：支持列表 → 详情 → 翻页；暂不执行网页 JavaScript。" :closable="false" />
                <div class="form-grid"><r-form-item label="列表条目 CSS"><r-input v-model="pipeline.html.item_selector" placeholder=".article-list .item" /></r-form-item><r-form-item label="详情链接 CSS（可选，相对每个条目）"><r-input v-model="pipeline.html.detail_selector" placeholder="a.title；留空则直接从列表提取" /></r-form-item><r-form-item label="下一页 CSS（可选）"><r-input v-model="pipeline.html.next_selector" placeholder="a.next" /></r-form-item></div>
                <p class="helper">配置详情链接后，字段从详情页提取。详情与翻页链接支持相对路径，须与列表同主机。</p>
              </template>
              <div class="form-grid"><r-form-item label="页码参数名（可选）"><r-input v-model="pipeline.request.page_param" placeholder="page；留空不按页码翻页" /></r-form-item><r-form-item label="起始页码"><r-input-number v-model="pipeline.request.start_page" :min="1" /></r-form-item></div>
              <p class="helper">页码参数追加到 URL；网页配置了“下一页 CSS”时优先跟随链接。</p>
              <r-collapse><r-collapse-item title="请求头与固定参数" name="request"><div class="form-grid"><r-form-item label="Headers（JSON 对象）"><r-input v-model="headersText" type="textarea" :rows="5" placeholder='{"Authorization":"Bearer ..."}' /></r-form-item><r-form-item label="Query 参数（JSON 对象）"><r-input v-model="paramsText" type="textarea" :rows="5" placeholder='{"limit":"50"}' /></r-form-item></div></r-collapse-item></r-collapse>
            </template>
            <template v-else-if="pipeline.input === 'database'">
              <div class="form-grid"><r-form-item label="数据库类型"><r-select v-model="pipeline.database.driver"><r-option v-for="driver in ['postgres', 'mysql', 'sqlite', 'sqlserver']" :key="driver" :label="dbNames[driver]" :value="driver" /></r-select></r-form-item><r-form-item label="服务端连接串环境变量"><r-input v-model="pipeline.database.dsn_env" placeholder="IMPORT_DATABASE_DSN" /></r-form-item></div>
              <r-alert title="连接串保存在后端环境变量中，规则只保存变量名。外部数据库请使用只读账号。" :closable="false" type="info" />
              <p class="helper">{{ dsnHint }}</p>
              <r-form-item label="读取 SQL（单条 SELECT，不带分号）"><r-input v-model="pipeline.database.query" type="textarea" :rows="6" placeholder="SELECT id, title, content FROM articles" /></r-form-item>
              <p class="helper">查询会作为子查询执行并限制记录数。需要排序时，请使用数据库允许放入子查询的语法。</p>
            </template>
            <template v-else>
              <label class="upload-zone"><strong>{{ uploading ? '正在上传…' : (pipeline.file.name || '选择 Excel / CSV 文件') }}</strong><span>.xlsx 或 UTF-8 .csv，最大 20 MB。旧 .xls 请先另存为 .xlsx。</span><input type="file" accept=".xlsx,.csv" :disabled="uploading" @change="onUpload" /></label>
              <div class="form-grid"><r-form-item label="工作表名称（Excel）"><r-input v-model="pipeline.file.sheet" placeholder="留空使用第一张工作表" /></r-form-item><r-form-item label="表头所在行"><r-input-number v-model="pipeline.file.header_row" :min="1" :max="100" /></r-form-item></div>
              <p class="helper">以表头列名映射字段，自动跳过空行。上传文件保留在服务端，重复运行使用同一份文件。</p>
            </template>
          </r-form>
        </section>

        <section v-show="step === 2">
          <div class="section-title"><div><h3>字段映射与清洗</h3><p class="helper">{{ mappingHint }}</p></div><r-button v-if="!isWebhookForm" @click="pipeline.fields.push(field())">添加字段</r-button></div>
          <r-alert v-if="isWebhookForm" title="Webhook 标准字段：title、content、summary、cover、category、url、source_name、published_at 等由推送 JSON 映射；按业务类型校验必填字段。下方表格仅作说明。" type="warning" :closable="false" />
          <r-alert v-else :title="schemaHint" :closable="false" />
          <fieldset class="mapping-table" :disabled="isWebhookForm"><r-table :data="pipeline.fields" border>
            <r-table-column type="expand"><template #default="{ row }"><div class="cleaning"><div class="form-grid"><r-form-item label="空值默认值"><r-input v-model="row.default" /></r-form-item><r-form-item label="正则替换表达式（Go RE2）"><r-input v-model="row.pattern" placeholder="例如：广告词|推广词" /></r-form-item><r-form-item label="替换为"><r-input v-model="row.replacement" placeholder="留空表示删除匹配内容" /></r-form-item></div><r-checkbox v-model="row.trim">去除首尾空白</r-checkbox><r-checkbox v-model="row.strip_html">移除 HTML 标签</r-checkbox></div></template></r-table-column>
            <r-table-column label="目标字段" min-width="150"><template #default="{ row }"><r-input v-model="row.target" placeholder="title" /></template></r-table-column>
            <r-table-column :label="pipeline.input === 'html' ? 'CSS 选择器' : (pipeline.input === 'api' ? 'JSON 路径' : '来源列名')" min-width="180"><template #default="{ row }"><r-input v-model="row.selector" :placeholder="pipeline.input === 'html' ? 'h1 / $url' : 'title'" /></template></r-table-column>
            <r-table-column v-if="pipeline.input === 'html'" label="提取内容" min-width="140"><template #default="{ row }"><r-select v-model="row.attribute" filterable allow-create default-first-option><r-option v-for="attr in ['text', 'html', 'href', 'src', 'content']" :key="attr" :label="attr" :value="attr" /></r-select></template></r-table-column>
            <r-table-column label="必填" width="65"><template #default="{ row }"><r-checkbox v-model="row.required" :aria-label="`${row.target} 必填`" /></template></r-table-column>
            <r-table-column width="70"><template #default="{ $index }"><r-button type="danger" link @click="pipeline.fields.splice($index, 1)">删除</r-button></template></r-table-column>
          </r-table></fieldset>
          <p class="helper">展开每行设置清洗规则，按“默认值 → 去 HTML → 正则替换 → 去空白 → 必填校验”执行。play_url 支持通过 # 分集与 $ 分隔名称/播放地址（如 第01集$http...#第02集$http...），多线路通过 $$$ 分隔。</p>
          <div class="form-grid"><r-form-item label="唯一标识字段"><r-select v-model="pipeline.key_field"><r-option v-for="f in pipeline.fields.filter(f => f.target)" :key="f.target" :label="f.target" :value="f.target" /></r-select></r-form-item><r-form-item label="遇到重复记录"><r-select v-model="pipeline.duplicate"><r-option label="更新已有记录" value="update" /><r-option label="跳过已有记录" value="skip" /></r-select></r-form-item></div>
          <p class="helper">同一规则、同一内容类型按唯一标识去重。建议使用来源 ID 或详情 URL。文章已发布或已隐藏时保留编辑结果；视频库仍按现有片名聚合。</p>
        </section>

        <section v-show="step === 3">
          <div class="section-title"><div><h3>先看样本，再运行</h3><p class="helper">最多读取 10 条样本，预览不写入内容库。</p></div><r-button type="primary" plain :loading="previewing" @click="preview">测试并预览</r-button></div>
          <r-alert v-if="previewError" :title="previewError" type="error" :closable="false" />
          <r-alert v-else-if="previewed" :title="`预览 ${samples.length} 条 · ${samples.filter(s => s.errors.length).length} 条校验失败`" :type="samples.some(s => s.errors.length) ? 'warning' : 'success'" :closable="false" />
          <r-empty v-if="!samples.length" :description="previewed ? '未提取到记录，请检查路径、选择器或来源数据' : '点击测试并预览，检查提取结果'" :image-size="70" />
          <template v-else><r-segmented v-model="sampleMode" :options="[{ label: '清洗结果', value: 'values' }, { label: '原始提取值', value: 'raw' }]" class="sample-mode" /><r-table :data="samples" border max-height="320"><r-table-column v-for="f in pipeline.fields" :key="f.target" :label="f.target" min-width="170" show-overflow-tooltip><template #default="{ row }">{{ row[sampleMode][f.target] }}</template></r-table-column><r-table-column label="校验" min-width="210"><template #default="{ row }"><span :class="{ invalid: row.errors.length }">{{ row.errors.join('；') || '通过' }}</span></template></r-table-column></r-table></template>
          <h3>运行策略</h3><div class="form-grid limits"><r-form-item label="每次最多记录"><r-input-number v-model="pipeline.max_records" :min="1" :max="10000" /></r-form-item><r-form-item label="每次最多页数"><r-input-number v-model="form.page_limit" :min="1" :max="100" /></r-form-item><r-form-item label="请求超时 / 秒"><r-input-number v-model="form.timeout_sec" :min="1" :max="60" /></r-form-item><r-form-item label="请求间隔 / 毫秒"><r-input-number v-model="form.interval_ms" :min="0" :max="10000" :step="100" /></r-form-item><r-form-item label="失败重试次数"><r-input-number v-model="form.retry_count" :min="0" :max="3" /></r-form-item><r-form-item label="加入全局自动调度"><r-switch v-model="form.enabled" /></r-form-item></div>
          <p class="helper">页数、重试、间隔作用于 HTTP 来源。通用规则支持在 Query 参数中使用 {hours}（增量小时）与 {page}（页码）宏变量。数据库和文件按记录上限读取。全局调度须在“定时调度”中开启。</p>
        </section>
        <footer class="editor-footer"><r-button :disabled="step === 0" @click="step--">上一步</r-button><div class="actions"><r-button :loading="saving" @click="save">{{ isWebhookForm ? '保存业务类型' : '保存规则' }}</r-button><r-button v-if="step < 3" type="primary" @click="step++">下一步</r-button><r-button v-else type="primary" :loading="running" :disabled="isWebhookForm" @click="run">保存并运行</r-button></div></footer>
      </main>
    </div>
    <!-- 采集结果与数据校正工作台 -->
    <r-dialog
      v-model="recordsVisible"
      :title="`采集结果与数据校正工作台 · ${form.name || '通用使魔'}`"
      width="min(1320px, 96vw)"
    >
      <div class="workbench-bar">
        <div class="bar-left">
          <div class="workbench-stats">
            <span class="wb-stat-pill"><r-icon :size="12"><Film /></r-icon> 总采集 <strong>{{ recordsTotal }}</strong> 条</span>
            <span class="wb-stat-pill warning"><r-icon :size="12"><Refresh /></r-icon> 待校正 <strong>{{ pendingCount }}</strong> 条</span>
            <span class="wb-stat-pill success"><r-icon :size="12"><Check /></r-icon> 已入库 <strong>{{ linkedCount }}</strong> 条</span>
          </div>
          <div class="wb-filters">
            <r-input
              v-model="recordKeyword"
              placeholder="按唯一标识或内容字段检索..."
              style="width: 240px;"
              clearable
            />
            <r-select v-model="recordStatusFilter" placeholder="入库状态 (全部)" style="width: 160px;" clearable>
              <r-option label="全部状态" value="" />
              <r-option label="待校正 · 未入库" value="pending" />
              <r-option label="已入库 Wiki/视频" value="linked" />
            </r-select>
          </div>
        </div>
        <div class="bar-right">
          <r-button type="primary" :loading="batchRectifying" @click="handleBatchRectify">
            <r-icon><Check /></r-icon>一键全量智能校正
          </r-button>
          <r-button type="success" plain :loading="importingSamples" @click="handleImportSamples">
            <r-icon><Plus /></r-icon>注入演职样本数据
          </r-button>
          <r-button :loading="recordsLoading" @click="loadRecords">
            <r-icon><Refresh /></r-icon>刷新数据
          </r-button>
        </div>
      </div>

      <div class="workbench-sub-banner">
        在此工作台可对已采集数据进行<strong>逐字段清洗纠偏</strong>，或<strong>一键校正入库至 Universal Wiki 实体图谱</strong>与视频库。
      </div>

      <r-table :data="filteredRecords" v-loading="recordsLoading" border stripe style="width: 100%; margin-top: 8px;">
        <r-table-column label="肖像 / 封面" width="80" align="center">
          <template #default="{ row }">
            <div class="table-thumb-wrap">
              <img
                v-if="row.values.avatar || row.values.cover || row.values.picture || row.values.profile_path"
                :src="row.values.avatar || row.values.cover || row.values.picture || row.values.profile_path"
                class="table-thumb"
                loading="lazy"
              />
              <div v-else class="table-thumb-empty">
                {{ (row.values.name || row.values.title || row.key || 'D').slice(0, 1) }}
              </div>
            </div>
          </template>
        </r-table-column>
        <r-table-column label="实体名称 / 原名" min-width="180">
          <template #default="{ row }">
            <div class="cell-main-title">
              <div class="main-title-row">
                <strong class="entity-name">{{ row.values.name || row.values.title || row.key }}</strong>
                <span v-if="row.values.actor_id || row.values.movie_id" class="src-id-badge">
                  TMDB #{{ row.values.actor_id || row.values.movie_id }}
                </span>
              </div>
              <small v-if="row.values.original_name" class="sub-text">{{ row.values.original_name }}</small>
            </div>
          </template>
        </r-table-column>
        <r-table-column prop="key" label="来源唯一标识" min-width="140" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="key-code">{{ row.key }}</span>
          </template>
        </r-table-column>
        <r-table-column label="入库状态" width="150" align="center">
          <template #default="{ row }">
            <r-tag v-if="row.content_id > 0" type="success" size="small">
              已入库 Wiki #{{ row.content_id }}
            </r-tag>
            <r-tag v-else type="warning" size="small">待校正 · 未入库</r-tag>
          </template>
        </r-table-column>
        <r-table-column label="核心属性预览" min-width="250">
          <template #default="{ row }">
            <div class="pills-list">
              <span v-if="row.values.role_type" class="attr-pill role">
                <strong>工种:</strong> {{ row.values.role_type }}
              </span>
              <span v-if="row.values.gender" class="attr-pill">
                <strong>性别:</strong> {{ row.values.gender }}
              </span>
              <span v-if="row.values.known_for" class="attr-pill highlight">
                <strong>代表作:</strong> {{ row.values.known_for }}
              </span>
              <span v-if="row.values.birthday" class="attr-pill">
                <strong>生辰:</strong> {{ row.values.birthday }}
              </span>
              <span v-if="row.values.popularity" class="attr-pill pop">
                <strong>人气:</strong> {{ row.values.popularity }}
              </span>
              <span v-if="row.values.category" class="attr-pill">
                <strong>分类:</strong> {{ row.values.category }}
              </span>
              <span v-if="row.values.release_date" class="attr-pill">
                <strong>定档:</strong> {{ row.values.release_date }}
              </span>
            </div>
          </template>
        </r-table-column>
        <r-table-column prop="updated_at" label="采集时间" width="160" align="center">
          <template #default="{ row }">
            <span class="date-text">{{ row.updated_at }}</span>
          </template>
        </r-table-column>
        <r-table-column label="数据校正与入库" width="280" align="center" fixed="right">
          <template #default="{ row }">
            <div class="action-btn-group">
              <r-button size="small" type="primary" plain @click="openEditRecord(row)">校正数据</r-button>
              <r-button v-if="pipeline.target === 'video' || row.values?.play_url || row.values?.title" size="small" type="warning" @click="handleRectifyToVideo(row)">转入视频</r-button>
              <r-button size="small" type="success" @click="openRectifyToWiki(row)">转入 Wiki</r-button>
              <r-button size="small" type="danger" link @click="handleDeleteRecord(row)">删除</r-button>
            </div>
          </template>
        </r-table-column>
      </r-table>

      <div class="wb-pagination-bar">
        <span class="total-text">当前页已筛选出 {{ filteredRecords.length }} 条记录</span>
        <r-pagination
          v-model:current-page="recordsPage"
          v-model:page-size="recordsPageSize"
          :page-sizes="[10, 20, 50, 100]"
          :total="recordsTotal"
          @current-change="loadRecords"
          @size-change="loadRecords"
        />
      </div>
    </r-dialog>

    <!-- 弹窗 1：在线字段校正 -->
    <r-dialog v-model="editRecordVisible" title="在线字段校正与补全" width="680px">
      <div v-if="editingRecord" class="record-editor-box">
        <div class="editor-header-note">
          <p class="editor-sub-desc">修改提取出的键值对，补全错译、修正常用名或调整头像路径。</p>
          <div class="quick-presets">
            <span class="preset-label">快捷插入常用字段:</span>
            <span class="preset-btn" @click="quickAddField('known_for')">+ 代表作</span>
            <span class="preset-btn" @click="quickAddField('birthday')">+ 生辰</span>
            <span class="preset-btn" @click="quickAddField('role_type', 'suit_actor')">+ 皮套演员</span>
            <span class="preset-btn" @click="quickAddField('gender', '男')">+ 性别</span>
            <span class="preset-btn" @click="quickAddField('original_name')">+ 外文名</span>
            <span class="preset-btn" @click="quickAddField('popularity')">+ 人气</span>
          </div>
        </div>
        <r-table :data="editingFields" border size="small" style="width: 100%; margin: 12px 0;">
          <r-table-column label="字段名 (Key)" width="180">
            <template #default="{ row }">
              <r-input v-model="row.key" placeholder="如 name / birthday" size="small" />
            </template>
          </r-table-column>
          <r-table-column label="字段值 (Value)">
            <template #default="{ row }">
              <r-input v-model="row.value" placeholder="校正后的内容" size="small" />
            </template>
          </r-table-column>
          <r-table-column width="65" align="center">
            <template #default="{ $index }">
              <r-button type="danger" link size="small" @click="removeEditingField($index)">删除</r-button>
            </template>
          </r-table-column>
        </r-table>
        <r-button type="primary" plain size="small" @click="addEditingField">
          <r-icon><Plus /></r-icon>新增自定义属性
        </r-button>
      </div>
      <template #footer>
        <r-button @click="editRecordVisible = false">取消</r-button>
        <r-button type="primary" :loading="savingRecord" @click="saveRecordRectification">保存校正数据</r-button>
      </template>
    </r-dialog>

    <!-- 弹窗 2：校正并转入 Universal Wiki 知识库 -->
    <r-dialog v-model="wikiDialogVisible" title="校正并转入 Universal Wiki 知识库" width="min(840px, 95vw)">
      <r-form label-width="110px">
        <div class="form-grid" style="margin-top: 0; margin-bottom: 12px;">
          <r-form-item label="词条主名称" required>
            <r-input v-model="wikiForm.name" placeholder="例如：成龙 / 高岩成二 / 假面骑士极狐" />
          </r-form-item>
          <r-form-item label="外文/原名">
            <r-input v-model="wikiForm.original_name" placeholder="例如：Jackie Chan / Seiji Takaiwa" />
          </r-form-item>
        </div>
        <div class="form-grid" style="margin-top: 0; margin-bottom: 12px;">
          <r-form-item label="实体大类" required>
            <r-select v-model="wikiForm.type">
              <r-option label="👤 真实人物 (person)" value="person" />
              <r-option label="🎬 作品 (work)" value="work" />
              <r-option label="🎭 虚拟角色 (character)" value="character" />
              <r-option label="⏳ 纪元时间线 (event)" value="event" />
              <r-option label="🏢 机构制作方 (org)" value="org" />
            </r-select>
          </r-form-item>
          <r-form-item label="细分工种/领域" required>
            <r-select v-model="wikiForm.sub_type" filterable allow-create>
              <r-option label="皮套演员 (suit_actor)" value="suit_actor" />
              <r-option label="动作监督/武指 (martial_arts)" value="martial_arts" />
              <r-option label="声优/配音 (cv)" value="cv" />
              <r-option label="演员 (actor)" value="actor" />
              <r-option label="导演 (director)" value="director" />
              <r-option label="特摄作品 (tokusatsu)" value="tokusatsu" />
              <r-option label="番剧动画 (anime)" value="anime" />
              <r-option label="电影 (movie)" value="movie" />
              <r-option label="电视剧 (tv)" value="tv" />
              <r-option label="电子游戏 (game)" value="game" />
            </r-select>
          </r-form-item>
        </div>
        <r-form-item label="肖像/海报 URL">
          <div class="cover-input-box">
            <r-input v-model="wikiForm.cover_image" placeholder="https://image.tmdb.org/t/p/w500/..." style="flex: 1;" />
            <div v-if="wikiForm.cover_image" class="preview-mini-thumb">
              <img :src="wikiForm.cover_image" alt="preview" />
            </div>
          </div>
        </r-form-item>
        <r-form-item label="生平/剧情简介">
          <r-input v-model="wikiForm.summary" type="textarea" :rows="3" placeholder="人物生平或作品简介..." />
        </r-form-item>
        <r-form-item label="动态属性 (Infobox)">
          <div class="infobox-edit-box">
            <r-table :data="wikiForm.infoboxList" border size="small" style="width: 100%;">
              <r-table-column label="属性名称 (如 代表作/性别/出生日期/人气)" width="220">
                <template #default="{ row }">
                  <r-input v-model="row.key" size="small" placeholder="属性名" />
                </template>
              </r-table-column>
              <r-table-column label="属性值">
                <template #default="{ row }">
                  <r-input v-model="row.value" size="small" placeholder="属性值" />
                </template>
              </r-table-column>
              <r-table-column width="65" align="center">
                <template #default="{ $index }">
                  <r-button type="danger" link size="small" @click="wikiForm.infoboxList.splice($index, 1)">删除</r-button>
                </template>
              </r-table-column>
            </r-table>
            <r-button type="primary" plain size="small" style="margin-top: 6px;" @click="wikiForm.infoboxList.push({ key: '', value: '' })">
              <r-icon><Plus /></r-icon>添加属性
            </r-button>
          </div>
        </r-form-item>
        <r-form-item label="曾用名 / 别名">
          <r-input v-model="wikiForm.aliasesText" type="textarea" :rows="2" placeholder="每行一个别名，例如：陈港生&#10;房仕龙" />
        </r-form-item>
      </r-form>
      <template #footer>
        <r-button @click="wikiDialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="wikiSubmitting" @click="submitRectifyToWiki">确认校正并入库 Wiki</r-button>
      </template>
    </r-dialog>

    <!-- 弹窗 3：使魔规则采集运行进程与实时日志 -->
    <r-dialog
      v-model="ruleLogsVisible"
      :title="`使魔采集运行进程与实时日志 · ${form.name || form.id}`"
      width="min(960px, 95vw)"
    >
      <div v-if="latestTask" class="rule-task-banner">
        <div class="banner-top">
          <div class="banner-status">
            <r-tag v-if="latestTask.status === 'running'" type="warning" size="small" class="running-pill">
              <r-icon class="rotating-icon" :size="11"><Refresh /></r-icon> 使魔正在采集中...
            </r-tag>
            <r-tag v-else-if="latestTask.status === 'success'" type="success" size="small">
              <r-icon :size="11"><Check /></r-icon> 采集已圆满完成
            </r-tag>
            <r-tag v-else-if="latestTask.status === 'failed'" type="danger" size="small">
              采集失败中止
            </r-tag>
            <span class="task-no">任务批次 #{{ latestTask.id }}</span>
            <span class="task-time">启动于 {{ formatDateTime(latestTask.started_at) }}</span>
          </div>
          <div class="banner-duration">
            耗时：<strong>{{ formatTaskDuration(latestTask.duration_ms, latestTask.status === 'running') }}</strong>
          </div>
        </div>

        <div class="banner-metrics">
          <div class="metric-block">
            <span class="m-lbl">读取/抓取</span>
            <strong class="m-val">{{ latestTask.total_fetched }} 条</strong>
          </div>
          <div class="metric-block highlight">
            <span class="m-lbl">有效入库/新增</span>
            <strong class="m-val">{{ latestTask.total_saved }} 条</strong>
          </div>
          <div class="metric-block">
            <span class="m-lbl">过滤/跳过</span>
            <strong class="m-val">{{ latestTask.total_skipped }} 条</strong>
          </div>
        </div>

        <div v-if="latestTask.error_message" class="banner-error">
          <span>错误提示：</span>{{ latestTask.error_message }}
        </div>
      </div>
      <div v-else class="rule-task-banner empty">
        <span>当前规则暂无执行记录或正等待任务初始化...</span>
      </div>

      <!-- 实时日志视窗 -->
      <div class="rule-log-terminal">
        <div class="terminal-bar">
          <span>实时执行日志流 ({{ currentRuleLogs.length }} 行)</span>
          <div class="bar-btns">
            <r-button size="small" link @click="loadRuleLogs">
              <r-icon><Refresh /></r-icon>刷新
            </r-button>
            <r-button size="small" link @click="copyRuleLogs">复制日志</r-button>
          </div>
        </div>
        <div class="terminal-content">
          <div v-if="!currentRuleLogs.length" class="empty-terminal">
            正在建立日志连接或等待采集输出...
          </div>
          <div v-for="l in currentRuleLogs" :key="l.id" class="term-line">
            <span class="term-time">{{ formatTime(l.created_at) }}</span>
            <span :class="['term-lvl', l.level.toLowerCase()]">[{{ l.level }}]</span>
            <span class="term-text">{{ l.message }}</span>
          </div>
        </div>
      </div>

      <template #footer>
        <div class="rule-log-footer">
          <r-button type="success" plain :disabled="!isSaved" @click="jumpToRecords">
            <r-icon><Film /></r-icon>进入采集数据工作台
          </r-button>
          <r-button @click="ruleLogsVisible = false">关闭</r-button>
        </div>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref, reactive, watch } from 'vue'
import { onBeforeRouteLeave } from 'vue-router'
import { notify, confirmAction }  from '@/components/radix/feedback'
import { Zap, ArrowDown, Refresh, Plus, Film, Check, Activity } from '@/components/radix/icons'
import { listBusinessTypes } from '@/api/businessTypes'
import type { BusinessType } from '@/api/businessTypes'
import { getSources, saveSource, deleteSource, triggerCollect, triggerCollectAll } from '@/api/admin'
import {
  collectionRecords,
  updateCollectionRecord,
  deleteCollectionRecord,
  rectifyRecordToWiki,
  rectifyRecordToVideo,
  batchRectifyRecords,
  importSampleRecords,
  getCollectionTasks,
  getCollectionLogs,
  field,
  newRule,
  previewCollection,
  uploadCollection,
  newTMDBPopularActorsPreset,
  newTMDBSearchPersonPreset,
  newTMDBMoviePreset,
  newStandardVideoPreset,
  newAGIHuntPreset
} from '@/api/collection'
import type { CollectedRecord, CollectionTask, CollectionLog, PipelineRule, PipelineSource, Sample } from '@/api/collection'

const sourceOptions: { value: PipelineRule['input']; label: string; icon: string; description: string }[] = [
  { value: 'api', label: '接口采集', icon: '{ }', description: 'JSON · GET / POST · 字段路径' },
  { value: 'rss', label: 'RSS / 资讯', icon: '📡', description: 'RSS 2.0 / Atom · 实时快讯 / 简报' },
  { value: 'html', label: '网页采集', icon: '</>', description: '列表 / 详情 · CSS · 翻页' },
  { value: 'database', label: '数据库导入', icon: 'DB', description: 'PostgreSQL / MySQL / SQLite / SQL Server' },
  { value: 'file', label: 'Excel / CSV', icon: '▦', description: '上传文件 · 工作表 · 按列映射' }
]
const dbNames: Record<string, string> = { postgres: 'PostgreSQL', mysql: 'MySQL', sqlite: 'SQLite', sqlserver: 'SQL Server' }
const form = ref<PipelineSource>(newRule())
const pipeline = computed(() => form.value.filter.pipeline)
const rules = ref<PipelineSource[]>([])
const step = ref(0), search = ref(''), loading = ref(false), saving = ref(false), running = ref(false), uploading = ref(false)
const headersText = ref('{}'), paramsText = ref('{}')
const snapshot = () => JSON.stringify([form.value, headersText.value, paramsText.value])
const savedSnapshot = ref(snapshot())
const dirty = computed(() => snapshot() !== savedSnapshot.value)
const isSaved = computed(() => rules.value.some(r => r.id === form.value.id))
const filteredRules = computed(() => rules.value.filter(r => r.name.toLowerCase().includes(search.value.toLowerCase())))
function isWebhookSource(src: any): boolean {
  return src?.type === 'webhook' || String(src?.api || '').startsWith('webhook://')
}
const inputLabel = (input: string) => input === 'webhook' ? 'Webhook 推送' : (sourceOptions.find(o => o.value === input)?.label || input)
const businessTypes = ref<BusinessType[]>([])
const targetLabel = (target: string) => businessTypes.value.find(type => type.slug === target)?.name || ({ record: '通用数据', article: '文章', video: '视频' } as Record<string, string>)[target] || target
const selectedBusinessType = computed(() => businessTypes.value.find(type => type.slug === pipeline.value.target))
const schemaHint = computed(() => {
  const fields = selectedBusinessType.value?.fields || []
  return fields.length ? fields.map(field => `${field.name} (${field.data_type}${field.required ? '，必填' : ''})`).join('；') : '保留所有映射字段到采集结果。可在「业务类型」中添加字段。'
})
const isWebhookForm = computed(() => isWebhookSource(form.value))
const targetHint = computed(() => {
  if (selectedBusinessType.value?.description) return selectedBusinessType.value.description
  return ({ record: '保留自定义字段，保存到采集结果，适合爬虫数据与后续业务扩展。', article: '映射标题和正文，采集后生成资讯草稿，可通过资讯管理接口审核发布。', video: '映射片名、封面和播放链接，接入现有视频仓库与片名聚合逻辑。' } as Record<string, string>)[pipeline.value.target] || '按业务类型配置的字段校验并入库。'
})
const mappingHint = computed(() => pipeline.value.input === 'webhook' ? '字段由推送方 JSON 映射；按所选业务类型入库，下方映射仅作说明。' : pipeline.value.input === 'rss' ? '支持 title、description/content、summary、link/url、pub_date、author/creator、category、cover。' : pipeline.value.input === 'html' ? '填写 CSS 选择器；$url 表示当前页面地址。href / src 会自动补全相对地址。' : pipeline.value.input === 'api' ? '支持 data.title 等点分路径与数组下标（如 images.0.url）。' : '来源列名必须与数据库列名或文件表头完全一致，可使用中文列名。')
const dsnHint = computed(() => ({ postgres: '格式：postgres://user:password@host:5432/database?sslmode=require', mysql: '格式：user:password@tcp(host:3306)/database', sqlite: '格式：file:/absolute/path/source.db?mode=ro', sqlserver: '格式：sqlserver://user:password@host:1433?database=database' }[pipeline.value.database.driver]))
const samples = ref<Sample[]>([]), previewed = ref(false), previewing = ref(false), previewError = ref('')
const sampleMode = ref('values')
let previewRevision = 0
watch([form, headersText, paramsText], () => { previewRevision++; samples.value = []; previewed.value = false; previewError.value = '' }, { deep: true, flush: 'sync' })

async function discardChanges() {
  if (!dirty.value) return true
  try { await confirmAction('当前修改尚未保存，确定放弃这些修改吗？', '未保存修改', { type: 'warning', confirmButtonText: '放弃修改', cancelButtonText: '继续编辑' }); return true } catch { return false }
}
function selectRule(rule: PipelineSource) {
  form.value = JSON.parse(JSON.stringify(rule))
  headersText.value = JSON.stringify(rule.headers || {}, null, 2)
  paramsText.value = JSON.stringify(rule.custom_params || {}, null, 2)
  step.value = 0; savedSnapshot.value = snapshot()
}
async function createRule(input: PipelineRule['input']) { if (await discardChanges()) selectRule(newRule(input)) }
async function applyPreset(cmd: string) {
  if (!(await discardChanges())) return
  if (cmd === 'standard_video') {
    selectRule(newStandardVideoPreset())
    notify('已载入标准影视 JSON 预设规则！支持影视多集切分与线路解析，请在第二步填入您的采集源 API 地址即可运行。', 'success')
  } else if (cmd === 'agihunt_ai_news') {
    selectRule(newAGIHuntPreset())
    notify('已载入 AGI Hunt · AI 实时快讯预设规则！已配置 RSS 2.0 订阅源与文章草稿映射，可直接预览或运行入库。', 'success')
  } else if (cmd === 'tmdb_popular_person') {
    selectRule(newTMDBPopularActorsPreset())
    notify('已载入 TMDB 官方预设规则！请在第二步请求参数中填入您的 api_key 即可直接测试预览与运行。', 'success')
  } else if (cmd === 'tmdb_search_person') {
    selectRule(newTMDBSearchPersonPreset())
    notify('已载入 TMDB 官方预设规则！请在第二步请求参数中填入您的 api_key 即可直接测试预览与运行。', 'success')
  } else if (cmd === 'tmdb_movie') {
    selectRule(newTMDBMoviePreset())
    notify('已载入 TMDB 官方预设规则！请在第二步请求参数中填入您的 api_key 即可直接测试预览与运行。', 'success')
  }
}
async function handleCollectAll(hours: number) {
  try {
    const text = hours === 0 ? '全量采集' : `近 ${hours} 小时增量采集`
    await confirmAction(`确定对所有启用的数据源执行【${text}】吗？`, '一键采集确认', {
      type: 'warning',
      confirmButtonText: '立即采集',
      cancelButtonText: '取消'
    })
    const res = await triggerCollectAll(hours)
    if (res.code === 1) {
      notify(res.msg || '采集任务已提交', 'success')
    }
  } catch (error: any) {
    if (error !== 'cancel') {
      notify(error.message || '触发失败', 'error')
    }
  }
}
async function handleRectifyToVideo(row: CollectedRecord) {
  const v = row.values || {}
  try {
    await confirmAction(`确定将【${v.title || v.name || row.key}】校正并直接入库至视频仓库吗？`, '校正转入视频库', { type: 'info' })
    const res = await rectifyRecordToVideo({
      source_id: form.value.id,
      target: form.value.filter.pipeline.target || 'video',
      key: row.key,
      play_url: v.play_url || '',
      play_from: v.play_from || 'm3u8',
      video: {
        name: v.title || v.name || row.key,
        picture: v.cover || v.picture || v.avatar || '',
        content: v.content || v.overview || v.summary || '',
        year: v.year || v.release_date || '',
        target_type_name: v.category || '',
        actor: v.actor || '',
        director: v.director || '',
        area: v.area || '',
        remarks: v.remarks || ''
      }
    })
    if (res.code === 1 && res.data) {
      notify('已成功校正并同步入库至视频库！', 'success')
      row.content_id = res.data.id
      loadRecords()
    }
  } catch (e: any) {
    if (e !== 'cancel') notify(e.message || '转入视频库失败', 'error')
  }
}
function adaptToPipeline(src: any): PipelineSource {
  if (src.type === 'pipeline' && src.filter?.pipeline) {
    return src as PipelineSource
  }
  // Webhook 保持推送源身份，业务类型默认文章，可独立配置。
  if (isWebhookSource(src)) {
    return {
      id: src.id,
      name: src.name + (src.type && src.type !== 'rule' ? ` (${src.type})` : ''),
      type: 'webhook',
      api: src.api || 'webhook://collector',
      active: src.active !== undefined ? src.active : src.enabled !== false,
      enabled: src.enabled !== undefined ? src.enabled : src.active !== false,
      collect_hours: src.collect_hours ?? 0,
      page_limit: src.page_limit || 1,
      timeout_sec: src.timeout_sec || 15,
      retry_count: src.retry_count || 0,
      interval_ms: src.interval_ms || 0,
      headers: src.headers || {},
      custom_params: src.custom_params || {},
      filter: {
        pipeline: {
          version: 1,
          input: 'webhook',
          target: src.filter?.pipeline?.target || 'article',
          key_field: 'external_id',
          duplicate: 'update',
          max_records: 200,
          request: { method: 'POST', body: '', list_path: '', page_param: '', start_page: 1 },
          html: { item_selector: '', detail_selector: '', next_selector: '' },
          database: { driver: 'postgres', dsn_env: '', query: '' },
          file: { token: '', name: '', sheet: '', header_row: 1 },
          fields: [
            { target: 'title', selector: 'title_zh', attribute: 'text', default: '', required: true, trim: true, strip_html: true, pattern: '', replacement: '' },
            { target: 'content', selector: 'summary_zh', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
            { target: 'summary', selector: 'summary_zh', attribute: 'text', default: '', required: false, trim: true, strip_html: true, pattern: '', replacement: '' },
            { target: 'cover', selector: 'images', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
            { target: 'category', selector: 'category', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
            { target: 'url', selector: 'url', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
            { target: 'source_name', selector: 'source_name', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
            { target: 'published_at', selector: 'published_at', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
            { target: 'external_id', selector: 'id', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' }
          ]
        }
      }
    }
  }
  return {
    id: src.id,
    name: src.name + (src.type && src.type !== 'rule' ? ` (${src.type})` : ''),
    type: 'pipeline',
    api: src.api,
    active: src.active !== undefined ? src.active : src.enabled !== false,
    enabled: src.enabled !== undefined ? src.enabled : src.active !== false,
    collect_hours: src.collect_hours ?? 24,
    page_limit: src.page_limit || 10,
    timeout_sec: src.timeout_sec || 15,
    retry_count: src.retry_count || 0,
    interval_ms: src.interval_ms || 300,
    headers: src.headers || {},
    custom_params: src.custom_params || { ac: 'detail', h: '{hours}' },
    filter: {
      pipeline: {
        version: 1,
        input: 'api',
        target: 'video',
        key_field: 'title',
        duplicate: 'update',
        max_records: 200,
        request: { method: 'GET', body: '', list_path: 'list', page_param: 'pg', start_page: 1 },
        html: { item_selector: '', detail_selector: '', next_selector: '' },
        database: { driver: 'postgres', dsn_env: '', query: '' },
        file: { token: '', name: '', sheet: '', header_row: 1 },
        fields: [
          { target: 'title', selector: 'vod_name', attribute: 'text', default: '', required: true, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'play_url', selector: 'vod_play_url', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'play_from', selector: 'vod_play_from', attribute: 'text', default: 'm3u8', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'cover', selector: 'vod_pic', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'category', selector: 'type_name', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'year', selector: 'vod_year', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'remarks', selector: 'vod_remarks', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'actor', selector: 'vod_actor', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'director', selector: 'vod_director', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'area', selector: 'vod_area', attribute: 'text', default: '', required: false, trim: true, strip_html: false, pattern: '', replacement: '' },
          { target: 'content', selector: 'vod_content', attribute: 'text', default: '', required: false, trim: true, strip_html: true, pattern: '', replacement: '' }
        ]
      }
    }
  }
}
async function editRule(rule: PipelineSource) { if (rule.id === form.value.id) return; if (await discardChanges()) selectRule(rule) }
function cloneRule() { form.value.id = 'rule_' + crypto.randomUUID(); form.value.name += '（副本）'; form.value.enabled = false; form.value.active = false; notify('副本已创建，保存后可独立运行', 'success') }
async function loadRules() {
  loading.value = true
  try {
    const res = await getSources()
    rules.value = (res.data || []).map(adaptToPipeline)
  } finally {
    loading.value = false
  }
}
function stringMap(text: string, label: string): Record<string, string> {
  const obj: unknown = JSON.parse(text || '{}')
  if (!obj || Array.isArray(obj) || typeof obj !== 'object' || Object.values(obj).some(v => typeof v !== 'string')) throw new Error(label + ' 必须是值为字符串的 JSON 对象')
  return obj as Record<string, string>
}
function payload() {
  const data = JSON.parse(JSON.stringify(form.value)) as PipelineSource
  data.headers = stringMap(headersText.value, 'Headers'); data.custom_params = stringMap(paramsText.value, 'Query 参数')
  data.active = data.enabled
  return data
}
async function save() {
  if (isWebhookForm.value) {
    saving.value = true
    try {
      const source = (await getSources()).data?.find(source => source.id === form.value.id)
      if (!source) throw new Error('采集源不存在，请刷新规则')
      await saveSource({ ...source, filter: { ...source.filter, pipeline: { ...source.filter?.pipeline, target: pipeline.value.target } } })
      savedSnapshot.value = snapshot()
      await loadRules()
      notify('Webhook 业务类型已保存', 'success')
      return true
    } catch { return false } finally { saving.value = false }
  }
  if (!form.value.name.trim()) { notify('请填写规则名称', 'warning'); step.value = 0; return false }
  saving.value = true
  try { const data = payload(); await saveSource(data); form.value = data; savedSnapshot.value = snapshot(); await loadRules(); notify('规则已保存', 'success'); return true }
  catch (e) { if (e instanceof SyntaxError) notify('请求头或参数 JSON 格式不正确', 'error'); else if (e instanceof Error && e.message.includes('JSON 对象')) notify(e.message, 'error'); return false }
  finally { saving.value = false }
}
async function preview() {
  if (isWebhookForm.value) {
    previewError.value = 'Webhook 源无法主动预览拉取，请由推送方 POST /api/webhooks/collector 验证入库。'
    previewed.value = true
    samples.value = []
    return
  }
  previewing.value = true; previewError.value = ''; const revision = previewRevision
  try { const res = await previewCollection(payload()); if (revision === previewRevision) { samples.value = res.data || []; previewed.value = true } }
  catch (e: any) { if (revision === previewRevision) previewError.value = e.response?.data?.error || e.message || '预览失败' }
  finally { previewing.value = false }
}
async function run() {
  if (isWebhookForm.value) {
    notify('Webhook 源不能主动拉取，请等待推送方推送或到「使魔节点管理」检查配置。', 'warning')
    return
  }
  running.value = true
  try {
    if (await save()) {
      await triggerCollect(form.value.id, 0)
      notify('已成功启动使魔全量采集流水线！可在进程与日志视窗查看实时进度', 'success')
      openRuleLogs()
    }
  } finally {
    running.value = false
  }
}
async function removeRule() {
  try { await confirmAction(`删除规则“${form.value.name}”？已采集内容会保留。`, '删除规则', { type: 'warning' }) } catch { return }
  await deleteSource(form.value.id); await loadRules(); selectRule(newRule()); notify('规则已删除', 'success')
}
async function onUpload(event: Event) {
  const input = event.target as HTMLInputElement; const file = input.files?.[0]; if (!file) return
  if (file.size > 20 * 1024 * 1024) { notify('文件不能超过 20 MB', 'error'); input.value = ''; return }
  uploading.value = true; const ruleID = form.value.id
  try { const res = await uploadCollection(file); if (res.data && form.value.id === ruleID) Object.assign(pipeline.value.file, res.data) } finally { uploading.value = false; input.value = '' }
}

// 3. 规则采集进程与实时日志控制
const ruleLogsVisible = ref(false)
const latestTask = ref<CollectionTask | null>(null)
const currentRuleLogs = ref<CollectionLog[]>([])
const ruleLogLoading = ref(false)
const isRuleRunning = computed(() => latestTask.value?.status === 'running')
let ruleLogTimer: any = null

const formatDateTime = (val?: string) => {
  if (!val) return ''
  return val.replace('T', ' ').substring(0, 19)
}

const formatTime = (val?: string) => {
  if (!val) return ''
  const t = val.replace('T', ' ')
  return t.length > 23 ? t.substring(11, 23) : t.substring(11, 19)
}

const formatTaskDuration = (ms?: number, isRunning?: boolean) => {
  if (isRunning) return '进行中...'
  if (!ms || ms <= 0) return '< 1s'
  const sec = Math.round(ms / 1000)
  if (sec < 60) return `${sec}秒`
  const min = Math.floor(sec / 60)
  const remainSec = sec % 60
  return `${min}分${remainSec}秒`
}

async function loadRuleLogs() {
  if (!form.value.id) return
  ruleLogLoading.value = true
  try {
    const [tasksRes, logsRes] = await Promise.all([
      getCollectionTasks({ source_id: form.value.id, page: 1, page_size: 1 }),
      getCollectionLogs({ source_id: form.value.id, page: 1, page_size: 100 })
    ])
    if (tasksRes.code === 1 && tasksRes.data && tasksRes.data.length > 0) {
      latestTask.value = tasksRes.data[0]
    }
    if (logsRes.code === 1 && logsRes.data) {
      currentRuleLogs.value = logsRes.data
    }
  } finally {
    ruleLogLoading.value = false
  }
}

function openRuleLogs() {
  ruleLogsVisible.value = true
  loadRuleLogs()
  if (ruleLogTimer) clearInterval(ruleLogTimer)
  ruleLogTimer = setInterval(() => {
    if (ruleLogsVisible.value) {
      loadRuleLogs()
    } else {
      clearInterval(ruleLogTimer)
      ruleLogTimer = null
    }
  }, 2500)
}

function copyRuleLogs() {
  if (!currentRuleLogs.value.length) return
  const text = currentRuleLogs.value.map(l => `[${formatTime(l.created_at)}] [${l.level}] ${l.message}`).join('\n')
  navigator.clipboard.writeText(text)
  notify('采集日志已复制到剪贴板', 'success')
}

function jumpToRecords() {
  ruleLogsVisible.value = false
  showRecords()
}

const recordsVisible = ref(false), recordsLoading = ref(false), records = ref<CollectedRecord[]>([]), recordsPage = ref(1), recordsPageSize = ref(20), recordsTotal = ref(0)
const recordKeyword = ref(''), recordStatusFilter = ref(''), importingSamples = ref(false), batchRectifying = ref(false)

const pendingCount = computed(() => records.value.filter(r => !r.content_id || r.content_id <= 0).length)
const linkedCount = computed(() => records.value.filter(r => r.content_id > 0).length)

const filteredRecords = computed(() => {
  return records.value.filter(r => {
    if (recordStatusFilter.value === 'pending' && r.content_id > 0) return false
    if (recordStatusFilter.value === 'linked' && (!r.content_id || r.content_id <= 0)) return false
    if (!recordKeyword.value.trim()) return true
    const q = recordKeyword.value.trim().toLowerCase()
    if (r.key.toLowerCase().includes(q)) return true
    return Object.values(r.values || {}).some(v => String(v).toLowerCase().includes(q))
  })
})

async function loadRecords() {
  recordsLoading.value = true
  try {
    const res = await collectionRecords(form.value.id, recordsPage.value, recordsPageSize.value)
    records.value = res.data || []
    recordsTotal.value = res.total || 0
  } finally {
    recordsLoading.value = false
  }
}

async function showRecords() {
  recordsPage.value = 1
  recordKeyword.value = ''
  recordStatusFilter.value = ''
  records.value = []
  recordsVisible.value = true
  await loadRecords()
}

async function handleBatchRectify() {
  try {
    await confirmAction(`确定对当前规则下的所有未入库记录执行全量智能校正吗？系统将自动识别条目特征并转入 Wiki 词条或视频库。`, '全量智能校正', {
      type: 'primary',
      confirmButtonText: '开始校正',
      cancelButtonText: '取消'
    })
    batchRectifying.value = true
    const res = await batchRectifyRecords({
      source_id: form.value.id,
      target: form.value.filter.pipeline.target
    })
    notify(res.msg || `全量智能校正完成！成功关联 ${res.data?.rectified_count || 0} 条数据`, 'success')
    await loadRecords()
  } catch (e: any) {
    if (e !== 'cancel') notify(e.message || '批量校正失败', 'error')
  } finally {
    batchRectifying.value = false
  }
}

async function handleImportSamples() {
  importingSamples.value = true
  try {
    const res = await importSampleRecords(form.value.id, pipeline.value.target)
    notify(res.msg || '演职样本采集数据已成功注入！', 'success')
    recordsPage.value = 1
    await loadRecords()
  } finally {
    importingSamples.value = false
  }
}

// 1. 在线校正字段
const editRecordVisible = ref(false)
const editingRecord = ref<CollectedRecord | null>(null)
const editingFields = ref<{ key: string; value: string }[]>([])
const savingRecord = ref(false)

function openEditRecord(row: CollectedRecord) {
  editingRecord.value = row
  editingFields.value = Object.entries(row.values || {}).map(([k, v]) => ({ key: k, value: String(v) }))
  if (editingFields.value.length === 0) {
    editingFields.value = [{ key: '', value: '' }]
  }
  editRecordVisible.value = true
}

function addEditingField() {
  editingFields.value.push({ key: '', value: '' })
}

function quickAddField(key: string, defaultValue = '') {
  const existing = editingFields.value.find(f => f.key === key)
  if (!existing) {
    // If the only item is empty, replace it
    if (editingFields.value.length === 1 && !editingFields.value[0].key.trim()) {
      editingFields.value[0] = { key, value: defaultValue }
    } else {
      editingFields.value.push({ key, value: defaultValue })
    }
  }
}

function removeEditingField(index: number) {
  editingFields.value.splice(index, 1)
}

async function saveRecordRectification() {
  if (!editingRecord.value) return
  savingRecord.value = true
  try {
    const newValues: Record<string, string> = {}
    editingFields.value.forEach(f => {
      if (f.key.trim()) {
        newValues[f.key.trim()] = f.value
      }
    })
    await updateCollectionRecord({
      source_id: form.value.id,
      target: form.value.filter.pipeline.target,
      key: editingRecord.value.key,
      values: newValues
    })
    notify('数据校正已保存', 'success')
    editRecordVisible.value = false
    await loadRecords()
  } finally {
    savingRecord.value = false
  }
}

// 2. 校正并转入 Universal Wiki
const wikiDialogVisible = ref(false)
const wikiTargetRecord = ref<CollectedRecord | null>(null)
const wikiSubmitting = ref(false)
const wikiForm = reactive({
  name: '',
  original_name: '',
  type: 'person',
  sub_type: 'actor',
  summary: '',
  cover_image: '',
  infoboxList: [] as { key: string; value: string }[],
  aliasesText: ''
})

function openRectifyToWiki(row: CollectedRecord) {
  wikiTargetRecord.value = row
  const v = row.values || {}
  const isWork = pipeline.value.target === 'video' || !!v.title || !!v.movie_id || v.role_type === 'tokusatsu'
  wikiForm.type = isWork ? 'work' : 'person'
  wikiForm.sub_type = v.role_type || (isWork ? 'tokusatsu' : (v.gender ? 'actor' : 'actor'))
  wikiForm.name = v.name || v.title || row.key
  wikiForm.original_name = v.original_name || ''
  wikiForm.cover_image = v.avatar || v.cover || v.picture || v.profile_path || ''
  wikiForm.summary = v.biography || v.overview || v.content || v.summary || ''
  wikiForm.aliasesText = v.aliases || ''

  const excludeKeys = new Set(['name', 'title', 'original_name', 'avatar', 'cover', 'picture', 'profile_path', 'biography', 'overview', 'content', 'summary', 'aliases'])
  const infobox: { key: string; value: string }[] = []
  Object.entries(v).forEach(([k, val]) => {
    if (!excludeKeys.has(k) && val) {
      const labelMap: Record<string, string> = {
        gender: '性别',
        birthday: '出生日期',
        known_for: '代表作',
        popularity: '人气指数',
        role_type: '专业工种',
        category: '作品类型',
        release_date: '发布时间',
        actor_id: 'TMDB ID'
      }
      infobox.push({ key: labelMap[k] || k, value: String(val) })
    }
  })
  wikiForm.infoboxList = infobox.length ? infobox : [{ key: '', value: '' }]
  wikiDialogVisible.value = true
}

async function submitRectifyToWiki() {
  if (!wikiForm.name.trim()) {
    notify('词条主名称不能为空', 'warning')
    return
  }
  if (!wikiTargetRecord.value) return
  wikiSubmitting.value = true
  try {
    const infoboxObj: Record<string, any> = {}
    wikiForm.infoboxList.forEach(item => {
      if (item.key.trim() && item.value.trim()) {
        infoboxObj[item.key.trim()] = item.value.trim()
      }
    })
    const aliasesArr = wikiForm.aliasesText.split('\n').map(s => s.trim()).filter(Boolean)

    await rectifyRecordToWiki({
      source_id: form.value.id,
      target: form.value.filter.pipeline.target,
      key: wikiTargetRecord.value.key,
      subject: {
        name: wikiForm.name.trim(),
        original_name: wikiForm.original_name.trim(),
        type: wikiForm.type,
        sub_type: wikiForm.sub_type,
        summary: wikiForm.summary.trim(),
        cover_image: wikiForm.cover_image.trim(),
        infobox: infoboxObj,
        aliases: aliasesArr
      }
    })
    notify(`已成功校正并将【${wikiForm.name}】入库为 Wiki 实体！`, 'success')
    wikiDialogVisible.value = false
    await loadRecords()
  } finally {
    wikiSubmitting.value = false
  }
}

async function handleDeleteRecord(row: CollectedRecord) {
  try {
    await confirmAction(`确定删除记录【${row.key}】吗？`, '删除记录', { type: 'warning' })
    await deleteCollectionRecord({
      source_id: form.value.id,
      target: form.value.filter.pipeline.target,
      key: row.key
    })
    notify('记录已删除', 'success')
    await loadRecords()
  } catch {}
}

function beforeUnload(e: BeforeUnloadEvent) { if (dirty.value) { e.preventDefault(); e.returnValue = '' } }
onBeforeRouteLeave(discardChanges)
onMounted(() => { listBusinessTypes().then(res => { businessTypes.value = res.data || [] }); loadRules(); window.addEventListener('beforeunload', beforeUnload) })
onBeforeUnmount(() => window.removeEventListener('beforeunload', beforeUnload))
</script>

<style scoped lang="scss">
.collection-studio { max-width: 1600px; margin: auto; color: var(--text-primary); }
.studio-header, .editor-heading, .section-title, .editor-footer, .library-title { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.studio-header {
  margin-bottom: 14px;
  h1 { margin: 3px 0; font-size: 13px; font-weight: 700; letter-spacing: -0.01em; }
  p { margin: 0; font-size: 10px; color: var(--text-secondary); }
}
.eyebrow { font-size: 9.5px; letter-spacing: 1.5px; font-weight: 700; color: var(--brand); }
.actions { display: flex; gap: 6px; flex-wrap: wrap; .r-button + .r-button { margin-left: 0; } }
.studio-layout { display: grid; grid-template-columns: 210px minmax(0, 1fr); gap: 12px; align-items: start; }
.rule-library, .workspace { background: var(--card-bg, #fff); border: 1px solid var(--border-color); border-radius: 12px; }
.rule-library { padding: 12px; .r-input { margin: 8px 0; } }
.rule-item {
  display: flex; flex-direction: column; width: 100%; gap: 4px; text-align: left;
  padding: 8px 10px; border: 1px solid transparent; border-radius: 8px; background: transparent;
  cursor: pointer; color: inherit; margin: 3px 0; overflow-wrap: anywhere;
  span { font-weight: 600; font-size: 11.5px; }
  small { font-size: 10px; color: var(--text-secondary); }
  .enabled { color: #059669; }
  &.selected { background: var(--nav-bg-active, #eef2ff); border-color: var(--nav-border-light, #c7d2fe); color: var(--brand, #4338ca); }
  &:hover { background: var(--nav-bg-subtle, #f5f7ff); }
}
.workspace { padding: 16px; min-width: 0; }
.editor-heading { margin-bottom: 14px; h2 { font-size: 13px; font-weight: 700; margin: 0 0 2px; } }
.steps { margin-bottom: 18px; }
:deep(.r-step.is-simple .r-step__title) { max-width: none; white-space: nowrap; font-size: 11px; }
h3 { font-size: 12px; font-weight: 650; margin: 16px 0 8px; }
.helper { font-size: 10.5px; line-height: 1.6; color: var(--text-secondary); }
.source-cards {
  display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; margin: 14px 0;
  button {
    display: flex; flex-direction: column; align-items: flex-start; text-align: left; gap: 8px;
    border: 1px solid var(--border-color); background: var(--card-bg, #fff); border-radius: 8px;
    padding: 12px 10px; cursor: pointer; color: var(--text-regular);
    span { font-size: 18px; color: var(--brand); height: 22px; }
    strong { font-size: 11.5px; font-weight: 600; color: var(--text-primary); }
    small { font-size: 10px; line-height: 1.5; color: var(--text-secondary); }
    &.chosen { border-color: var(--brand); background: var(--nav-bg-subtle); box-shadow: 0 0 0 1px var(--brand); }
  }
}
.form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 14px; margin-top: 14px; }
.limits { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.upload-zone {
  display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 22px 14px;
  border: 1px dashed var(--nav-border-light, #a5b4fc); background: var(--nav-bg-subtle, #f8faff);
  border-radius: 8px; margin: 14px 0; cursor: pointer;
  strong { font-size: 12px; }
  span { font-size: 10.5px; color: var(--text-secondary); }
  input { max-width: 100%; }
}
.mapping-table { min-width: 0; padding: 0; border: 0; margin: 14px 0 0; overflow-x: auto; }
.cleaning { padding: 8px 16px 14px; background: rgba(20, 32, 57, 0.03); border-radius: 6px; }
.editor-footer { border-top: 1px solid var(--border-color); margin-top: 20px; padding-top: 14px; }
.invalid { color: #dc2626; }

:global(html.dark .collection-studio .source-cards button),
:global(html.dark .collection-studio .cleaning),
:global(html.dark .collection-studio .upload-zone) {
  background: rgba(255, 255, 255, 0.04);
  color: var(--text-primary);
  border-color: var(--border-color);
}
:global(html.dark .collection-studio .rule-item.selected),
:global(html.dark .collection-studio .source-cards button.chosen),
:global(html.dark .collection-studio .rule-item:hover) {
  background: rgba(126, 148, 255, 0.1);
  color: var(--brand);
  border-color: var(--brand);
}
@media (max-width: 1150px) { .source-cards { grid-template-columns: repeat(2, minmax(0, 1fr)); } .limits { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (min-width: 801px) and (max-width: 1250px) {
  .studio-layout { grid-template-columns: 1fr; }
  .rule-library { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; max-height: 180px; overflow-y: auto; }
  .library-title { min-width: 150px; }
  .rule-library .r-input { width: 180px; margin: 0; }
  .rule-library :deep(.r-empty), .rule-library > .helper, .rule-library > .r-divider { display: none; }
  .rule-item { width: 200px; margin: 0; }
  .steps { padding: 12px; }
}
@media (max-width: 800px) {
  .studio-layout { grid-template-columns: 1fr; }
  .rule-library { max-height: 220px; overflow-y: auto; }
  .workspace { padding: 12px; }
  .studio-header, .editor-heading { align-items: flex-start; flex-direction: column; }
  .form-grid { grid-template-columns: 1fr; }
  .steps { padding: 8px 4px; }
  :deep(.r-step__title) { font-size: 11px; }
}
</style>

<!-- 独立顶层样式：作用于采集结果工作台与数据校正弹窗（Teleport 至 body） -->
<style lang="scss">
.workbench-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  margin-bottom: 10px;
  flex-wrap: wrap;

  .bar-left {
    display: flex;
    flex-direction: column;
    gap: 8px;

    .workbench-stats {
      display: flex;
      gap: 6px;
      align-items: center;

      .wb-stat-pill {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        font-size: 11px;
        padding: 2px 8px;
        border-radius: 9999px;
        background: rgba(100, 116, 139, 0.08);
        color: var(--text-secondary);

        strong {
          color: var(--text-primary);
          font-weight: 700;
        }

        &.warning {
          background: rgba(245, 158, 11, 0.1);
          color: #d97706;
          strong { color: #b45309; }
        }

        &.success {
          background: rgba(16, 185, 129, 0.1);
          color: #059669;
          strong { color: #047857; }
        }
      }
    }

    .wb-filters {
      display: flex;
      gap: 8px;
      align-items: center;
    }
  }

  .bar-right {
    display: flex;
    align-items: center;
    gap: 8px;
  }
}

.workbench-sub-banner {
  font-size: 11.5px;
  line-height: 1.5;
  color: var(--text-secondary);
  background: var(--bg-hover, #f8fafc);
  padding: 6px 12px;
  border-radius: 6px;
  border: 1px solid var(--border-color);
  margin-bottom: 8px;

  strong {
    color: var(--text-primary);
  }
}

.table-thumb-wrap {
  width: 42px;
  height: 58px;
  border-radius: 6px;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--nav-bg-subtle, #f1f5f9);
  border: 1px solid var(--border-color);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);

  .table-thumb {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .table-thumb-empty {
    font-size: 14px;
    font-weight: 700;
    color: #94a3b8;
  }
}

.cell-main-title {
  display: flex;
  flex-direction: column;
  gap: 2px;

  .main-title-row {
    display: flex;
    align-items: center;
    gap: 6px;

    .entity-name {
      font-size: 13px;
      font-weight: 600;
      color: var(--text-primary);
    }

    .src-id-badge {
      font-size: 10px;
      font-family: ui-monospace, monospace;
      padding: 1px 5px;
      border-radius: 3px;
      background: rgba(99, 102, 241, 0.08);
      color: var(--brand);
    }
  }

  .sub-text {
    font-size: 11px;
    color: var(--text-secondary);
  }
}

.key-code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 11px;
  color: var(--text-secondary);
  background: rgba(100, 116, 139, 0.06);
  padding: 1px 4px;
  border-radius: 3px;
}

.pills-list {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  align-items: center;

  .attr-pill {
    font-size: 10.5px;
    background: rgba(100, 116, 139, 0.08);
    border: 1px solid rgba(148, 163, 184, 0.2);
    padding: 1px 6px;
    border-radius: 4px;
    color: var(--text-secondary);

    strong {
      color: var(--text-primary);
      margin-right: 2px;
    }

    &.role {
      background: rgba(59, 130, 246, 0.08);
      border-color: rgba(59, 130, 246, 0.2);
      color: #2563eb;
    }

    &.highlight {
      background: rgba(16, 185, 129, 0.08);
      border-color: rgba(16, 185, 129, 0.2);
      color: #059669;
    }

    &.pop {
      background: rgba(245, 158, 11, 0.08);
      border-color: rgba(245, 158, 11, 0.2);
      color: #d97706;
    }
  }
}

.action-btn-group {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
}

.wb-pagination-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: 14px;
  padding-top: 8px;
  border-top: 1px solid var(--border-color);

  .total-text {
    font-size: 11.5px;
    color: var(--text-secondary);
  }
}

.record-editor-box {
  .editor-header-note {
    background: var(--bg-hover, #f8fafc);
    padding: 10px 12px;
    border-radius: 6px;
    border: 1px solid var(--border-color);
    margin-bottom: 12px;

    .editor-sub-desc {
      font-size: 11.5px;
      color: var(--text-secondary);
      margin: 0 0 6px 0;
    }

    .quick-presets {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      align-items: center;

      .preset-label {
        font-size: 11px;
        color: var(--text-secondary);
        font-weight: 600;
      }

      .preset-btn {
        font-size: 10.5px;
        background: #fff;
        border: 1px solid var(--border-color);
        padding: 1px 7px;
        border-radius: 4px;
        color: var(--brand);
        cursor: pointer;
        transition: all 0.15s ease;

        &:hover {
          background: rgba(99, 102, 241, 0.08);
          border-color: var(--brand);
        }
      }
    }
  }
}

.cover-input-box {
  display: flex;
  gap: 10px;
  align-items: center;

  .preview-mini-thumb {
    width: 38px;
    height: 48px;
    border-radius: 4px;
    overflow: hidden;
    border: 1px solid var(--border-color);
    flex-shrink: 0;

    img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
  }
}

.infobox-edit-box { width: 100%; }

/* 弹窗 3：使魔规则采集运行进程与实时日志 */
.rule-task-banner {
  background: var(--bg-card-subtle, rgba(0, 0, 0, 0.02));
  border: 1px solid var(--border-color);
  border-radius: 8px;
  padding: 12px 16px;
  margin-bottom: 14px;

  &.empty {
    text-align: center;
    color: var(--text-secondary);
    padding: 16px;
    font-size: 12px;
  }

  .banner-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
    padding-bottom: 8px;
    border-bottom: 1px dashed var(--border-color);

    .banner-status {
      display: flex;
      align-items: center;
      gap: 10px;

      .running-pill {
        animation: pulse-glow 2s infinite ease-in-out;
      }

      .task-no {
        font-size: 11.5px;
        font-weight: 700;
        color: var(--text-primary);
        background: rgba(0, 0, 0, 0.05);
        padding: 2px 6px;
        border-radius: 4px;
      }

      .task-time {
        font-size: 11px;
        color: var(--text-secondary);
      }
    }

    .banner-duration {
      font-size: 12px;
      color: var(--text-secondary);
      strong {
        color: var(--brand);
      }
    }
  }

  .banner-metrics {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;

    .metric-block {
      background: #fff;
      border: 1px solid var(--border-color);
      border-radius: 6px;
      padding: 8px 12px;
      display: flex;
      flex-direction: column;
      gap: 3px;

      .m-lbl {
        font-size: 11px;
        color: var(--text-secondary);
      }

      .m-val {
        font-size: 15px;
        font-weight: 700;
        color: var(--text-primary);
      }

      &.highlight {
        background: rgba(103, 194, 58, 0.06);
        border-color: rgba(103, 194, 58, 0.3);
        .m-val {
          color: #67c23a;
        }
      }
    }
  }

  .banner-error {
    margin-top: 10px;
    font-size: 11.5px;
    color: #f56c6c;
    background: rgba(245, 108, 108, 0.08);
    border: 1px solid rgba(245, 108, 108, 0.2);
    border-radius: 4px;
    padding: 6px 10px;
    span {
      font-weight: 600;
    }
  }
}

.rule-log-terminal {
  border: 1px solid #2d3035;
  border-radius: 8px;
  overflow: hidden;

  .terminal-bar {
    background: #232529;
    color: #c0c4cc;
    padding: 6px 12px;
    font-size: 11.5px;
    font-weight: 600;
    display: flex;
    justify-content: space-between;
    align-items: center;

    .bar-btns {
      display: flex;
      gap: 8px;
    }
  }

  .terminal-content {
    background: #18191c;
    color: #e4e7ed;
    padding: 12px;
    max-height: 380px;
    min-height: 180px;
    overflow-y: auto;
    font-family: Consolas, Monaco, monospace;
    font-size: 11px;
    line-height: 1.6;

    .empty-terminal {
      color: #909399;
      text-align: center;
      padding: 30px 0;
    }

    .term-line {
      display: flex;
      gap: 8px;
      padding: 2px 0;
      border-bottom: 1px solid rgba(255, 255, 255, 0.02);

      .term-time {
        color: #858b97;
        flex-shrink: 0;
      }

      .term-lvl {
        font-weight: 700;
        flex-shrink: 0;

        &.info { color: #409eff; }
        &.success { color: #67c23a; }
        &.warn { color: #e6a23c; }
        &.error { color: #f56c6c; }
      }

      .term-text {
        color: #dcdfe6;
        word-break: break-all;
      }
    }
  }
}

.rule-log-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.rotating-icon {
  animation: spin 1.2s linear infinite;
  display: inline-block;
}

@keyframes pulse-glow {
  0% { box-shadow: 0 0 0 0 rgba(230, 162, 60, 0.4); }
  70% { box-shadow: 0 0 0 6px rgba(230, 162, 60, 0); }
  100% { box-shadow: 0 0 0 0 rgba(230, 162, 60, 0); }
}
</style>
