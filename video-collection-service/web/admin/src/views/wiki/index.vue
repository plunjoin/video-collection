<template>
  <div class="wiki-page">
    <r-card shadow="never" class="table-card">
      <!-- 头部操作区 -->
      <header class="wiki-header">
        <div class="header-left">
          <span class="eyebrow">词条与人物关系管理</span>
          <div class="title-row">
            <h1 class="page-title">Wiki 知识库</h1>
            <div class="stats-pills">
              <span class="stat-pill"><r-icon :size="12"><Film /></r-icon> 总词条 <strong>{{ total }}</strong></span>
              <span class="stat-pill primary"><r-icon :size="12"><Network /></r-icon> 作品 / 人物 / 角色 / 机构</span>
            </div>
          </div>
          <p class="sub-desc">整理作品和人物资料，补充主演、导演等关系，供知识库检索与问答使用。</p>
        </div>
        <div class="header-right">
          <r-button v-if="!readOnly" type="success" plain @click="openSyncDialog">
            <r-icon><Film /></r-icon>从视频库同步
          </r-button>
          <r-button v-if="!readOnly" type="primary" @click="openEditDialog()">
            <r-icon><Plus /></r-icon>新增 Wiki 词条
          </r-button>
          <r-button :loading="loading" @click="loadData">
            <r-icon><RefreshCw /></r-icon>刷新
          </r-button>
        </div>
      </header>

      <r-collapse class="usage-guide">
        <r-collapse-item title="怎么用 · 三步整理知识库" name="how-to">
          <ol>
            <li>新增词条或从视频库同步，先准备作品、人物等基础资料。</li>
            <li>打开词条的「关系网」，填写人物名称，选择主演（演员/出演）、导演等关系。</li>
            <li>保存后，词条和关系会进入 RAG 知识库，可到「RAG 知识库」搜索或提问。</li>
          </ol>
        </r-collapse-item>
      </r-collapse>

      <!-- 检索与多维分类过滤卡片 -->
      <div class="filter-bar">
        <div class="search-input-wrap">
          <r-input
            v-model="searchQuery"
            placeholder="按词条名称、外文名或简介模糊检索..."
            clearable
            @keyup.enter="handleSearch"
          />
        </div>
        <r-select v-model="filterType" placeholder="实体类别 (全部)" style="width: 170px;" clearable @change="handleSearch">
          <r-option label="全部大类" value="" />
          <r-option label="🎬 作品 (Work)" value="work" />
          <r-option label="👤 人物/演职 (Person)" value="person" />
          <r-option label="🎭 虚拟角色 (Character)" value="character" />
          <r-option label="⏳ 纪元时间线 (Event)" value="event" />
          <r-option label="🏢 组织厂商 (Org)" value="org" />
        </r-select>
        <r-select v-model="filterSubType" placeholder="细分工种 / 领域" style="width: 180px;" clearable @change="handleSearch">
          <r-option label="全部细分" value="" />
          <r-option label="特摄作品 (tokusatsu)" value="tokusatsu" />
          <r-option label="皮套演员 (suit_actor)" value="suit_actor" />
          <r-option label="动作监督/武指 (martial_arts)" value="martial_arts" />
          <r-option label="声优/配音 (cv)" value="cv" />
          <r-option label="演员 (actor)" value="actor" />
          <r-option label="导演 (director)" value="director" />
          <r-option label="番剧动画 (anime)" value="anime" />
          <r-option label="电子游戏 (game)" value="game" />
          <r-option label="宇宙纪元 (era)" value="era" />
          <r-option label="编年史 (timeline)" value="timeline" />
        </r-select>
        <div class="filter-actions">
          <r-button type="primary" @click="handleSearch">
            <r-icon><Search /></r-icon>查询
          </r-button>
          <r-button @click="resetFilters">重置</r-button>
        </div>
      </div>

      <!-- 词条展示表格 -->
      <r-table v-if="loading || tableData.length" :data="tableData" v-loading="loading" border stripe style="width: 100%">
        <r-table-column prop="id" label="ID" width="60" align="center">
          <template #default="{ row }">
            <span class="cell-id">#{{ row.id }}</span>
          </template>
        </r-table-column>
        <r-table-column label="肖像 / 封面" width="80" align="center">
          <template #default="{ row }">
            <div class="cover-wrapper">
              <img v-if="row.cover_image" :src="row.cover_image" :alt="row.name" class="table-cover" loading="lazy" />
              <div v-else class="cover-placeholder" :class="row.type">
                <span>{{ row.name ? row.name.slice(0, 1) : 'W' }}</span>
              </div>
            </div>
          </template>
        </r-table-column>
        <r-table-column prop="name" label="词条实体主名称" min-width="190">
          <template #default="{ row }">
            <div class="name-cell">
              <div class="title-line">
                <span class="main-name">{{ row.name }}</span>
              </div>
              <small v-if="row.original_name" class="sub-name" :title="row.original_name">{{ row.original_name }}</small>
              <div v-if="row.aliases && row.aliases.length" class="alias-chips">
                <span v-for="(alias, idx) in row.aliases.slice(0, 2)" :key="idx" class="alias-chip" :title="alias">
                  {{ alias }}
                </span>
                <span v-if="row.aliases.length > 2" class="alias-chip more" :title="row.aliases.slice(2).join(', ')">+{{ row.aliases.length - 2 }}</span>
              </div>
            </div>
          </template>
        </r-table-column>
        <r-table-column label="实体类型 / 领域" width="140" align="center">
          <template #default="{ row }">
            <div class="type-cell">
              <r-tag :type="getTypeTag(row.type)" size="small">
                {{ typeLabels[row.type] || row.type }}
              </r-tag>
              <span class="sub-type-badge">
                {{ subTypeLabels[row.sub_type] || row.sub_type || '通用' }}
              </span>
            </div>
          </template>
        </r-table-column>
        <r-table-column label="动态属性 (Infobox)" width="210">
          <template #default="{ row }">
            <div class="infobox-preview" v-if="row.infobox && Object.keys(row.infobox).length">
              <span v-for="(v, k) in getLimitedInfobox(row.infobox, 2)" :key="k" class="infobox-pill" :title="`${k}: ${v}`">
                <span class="pill-k">{{ k }}</span>
                <span class="pill-v">{{ v }}</span>
              </span>
              <span v-if="Object.keys(row.infobox).length > 2" class="infobox-more" :title="formatAllInfobox(row.infobox)">
                +{{ Object.keys(row.infobox).length - 2 }}项
              </span>
            </div>
            <span v-else class="text-muted-empty">基础通用属性</span>
          </template>
        </r-table-column>
        <r-table-column prop="summary" label="生平 / 设定说明" min-width="200">
          <template #default="{ row }">
            <p class="cell-summary" :title="row.summary">{{ row.summary || '暂无详细文字百科说明。' }}</p>
          </template>
        </r-table-column>
        <r-table-column label="图谱与关系操作" width="270" align="center" fixed="right">
          <template #default="{ row }">
            <div class="table-actions-row">
              <r-button size="small" type="success" plain @click="openGraphDialog(row)">
                <r-icon><Network /></r-icon>图谱
              </r-button>
              <r-button size="small" type="info" plain @click="openRelationsDialog(row)">
                关系网 <span class="rel-badge">{{ row.relation_count || 0 }}</span>
              </r-button>
              <r-button v-if="!readOnly" size="small" type="primary" link @click="openEditDialog(row)">编辑</r-button>
              <r-button v-if="!readOnly" size="small" type="danger" link @click="handleDelete(row)">删除</r-button>
            </div>
          </template>
        </r-table-column>
      </r-table>
      <r-empty v-else :description="hasFilters ? '没有符合条件的词条，试试调整筛选或重置。' : '还没有词条。先新增一个词条，或从视频库同步已有作品，再补充主演、导演等关系。'">
        <template #footer>
          <div class="empty-actions">
            <r-button v-if="hasFilters" @click="resetFilters">重置筛选</r-button>
            <r-button v-if="!readOnly" type="primary" @click="openEditDialog()">新增词条</r-button>
            <r-button v-if="!readOnly" @click="openSyncDialog">从视频库同步</r-button>
          </div>
        </template>
      </r-empty>

      <!-- 分页栏 -->
      <div class="pagination-bar">
        <r-pagination
          v-model:current-page="page"
          v-model:page-size="pageSize"
          :page-sizes="[10, 20, 50, 100]"
          :total="total"
          @current-change="loadData"
          @size-change="loadData"
        />
      </div>
    </r-card>

    <!-- 1. 新增/编辑词条弹窗 -->
    <r-dialog
      v-model="editDialogVisible"
      :title="editingId ? `编辑 Wiki 词条 · ${form.name || ''}` : '新建 Wiki 知识库词条'"
      width="min(820px, 95vw)"
      destroy-on-close
    >
      <r-form label-width="110px" class="wiki-form">
        <div class="form-row-grid">
          <r-form-item label="主名称" required>
            <r-input v-model="form.name" placeholder="例如：假面骑士极狐 / 高岩成二 / 宇宙世纪UC0079" />
          </r-form-item>
          <r-form-item label="原名 / 外文名">
            <r-input v-model="form.original_name" placeholder="例如：仮面ライダーギーツ / Seiji Takaiwa" />
          </r-form-item>
        </div>
        <div class="form-row-grid">
          <r-form-item label="实体大类" required>
            <r-select v-model="form.type">
              <r-option label="🎬 作品 (work)" value="work" />
              <r-option label="👤 真实人物 (person)" value="person" />
              <r-option label="🎭 虚拟角色 (character)" value="character" />
              <r-option label="⏳ 事件/时间线 (event)" value="event" />
              <r-option label="🏢 组织机构 (org)" value="org" />
            </r-select>
          </r-form-item>
          <r-form-item label="细分工种 / 领域">
            <r-select v-model="form.sub_type" filterable allow-create>
              <r-option label="特摄作品 (tokusatsu)" value="tokusatsu" />
              <r-option label="皮套演员 (suit_actor)" value="suit_actor" />
              <r-option label="动作监督/武指 (martial_arts)" value="martial_arts" />
              <r-option label="声优/配音 (cv)" value="cv" />
              <r-option label="演员 (actor)" value="actor" />
              <r-option label="导演 (director)" value="director" />
              <r-option label="番剧动画 (anime)" value="anime" />
              <r-option label="电子游戏 (game)" value="game" />
              <r-option label="虚构纪元 (era)" value="era" />
              <r-option label="编年史 (timeline)" value="timeline" />
            </r-select>
          </r-form-item>
        </div>
        <r-form-item label="封面 / 肖像照">
          <div class="cover-input-box">
            <r-input v-model="form.cover_image" placeholder="https://image.tmdb.org/t/p/w500/... 或任意图片直链" style="flex: 1;" />
            <div v-if="form.cover_image" class="preview-mini-thumb">
              <img :src="form.cover_image" alt="preview" />
            </div>
          </div>
        </r-form-item>
        <r-form-item label="别名 (每行一个)">
          <r-input v-model="aliasesText" type="textarea" :rows="2" placeholder="Masked Rider&#10;极狐&#10;Geats" />
        </r-form-item>
        <r-form-item label="生平 / 设定说明">
          <r-input v-model="form.summary" type="textarea" :rows="4" placeholder="词条详尽百科说明，支持 Markdown 格式" />
        </r-form-item>

        <!-- 动态属性卡 Infobox 编辑器 -->
        <r-collapse>
          <r-collapse-item title="动态属性卡 (Infobox 键值对扩展)" name="infobox">
            <div class="infobox-editor">
              <p class="editor-tip">可自由扩展工种定制属性，如代表皮套、出演年代、出生地、所属事务所、武器设定等：</p>
              <div v-for="(item, idx) in infoboxList" :key="idx" class="infobox-row">
                <r-input v-model="item.key" placeholder="属性名 (如: 代表作 / 出生日期 / 平台)" style="width: 35%;" />
                <r-input v-model="item.value" placeholder="属性值 (如: 假面骑士空我 / 1976-02-16)" style="width: 53%;" />
                <r-button type="danger" link @click="infoboxList.splice(idx, 1)">删除</r-button>
              </div>
              <r-button size="small" type="primary" plain @click="infoboxList.push({ key: '', value: '' })">
                <r-icon><Plus /></r-icon>添加自定义属性
              </r-button>
            </div>
          </r-collapse-item>
        </r-collapse>
      </r-form>
      <template #footer>
        <r-button @click="editDialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="submitting" @click="submitSubject">保存词条</r-button>
      </template>
    </r-dialog>

    <!-- 2. 关系网络拓扑抽屉 -->
    <r-dialog
      v-model="relationsVisible"
      :title="`【${currentSubject?.name || ''}】的多维关联关系网`"
      width="min(940px, 96vw)"
      destroy-on-close
    >
      <div v-loading="relationsLoading" class="relations-box">
        <!-- 实体卡片概览 -->
        <div class="subject-brief-card">
          <div class="brief-thumb">
            <img v-if="currentSubject?.cover_image" :src="currentSubject.cover_image" :alt="currentSubject.name" />
            <div v-else class="brief-thumb-empty">{{ currentSubject?.name?.slice(0, 1) }}</div>
          </div>
          <div class="brief-meta">
            <div class="brief-name">
              <h3>{{ currentSubject?.name }}</h3>
              <small v-if="currentSubject?.original_name">{{ currentSubject.original_name }}</small>
            </div>
            <div class="brief-tags">
              <r-tag size="small" :type="getTypeTag(currentSubject?.type)">{{ typeLabels[currentSubject?.type] }}</r-tag>
              <span class="sub-badge">{{ subTypeLabels[currentSubject?.sub_type] || currentSubject?.sub_type }}</span>
            </div>
          </div>
        </div>

        <!-- 快捷新增关系表单 -->
        <p class="relation-guide">例如：在作品词条中输入主演姓名，选择「演员/出演」，再点击「添加关系」。保存后会进入 RAG，用于检索和问答。</p>
        <div v-if="!readOnly" class="relation-add-bar">
          <div class="add-bar-header">
            <h4>添加人物或作品关系</h4>
            <span class="sub-note">目标词条不存在时，会自动创建基础词条并建立关系</span>
          </div>
          <div class="relation-form-row">
            <r-input v-model="relationTargetName" placeholder="目标词条名称 (如: 富永研司 / 假面骑士极狐)" style="width: 220px;" />
            <r-select v-model="relationType" placeholder="关系类型" style="width: 170px;">
              <r-option label="皮套演员 (suit_actor)" value="suit_actor" />
              <r-option label="动作监督/武指 (action_director)" value="action_director" />
              <r-option label="声优/配音 (cv)" value="cv" />
              <r-option label="演员/出演 (actor)" value="actor" />
              <r-option label="导演 (director)" value="director" />
              <r-option label="衍生游戏 (game_adaptation)" value="game_adaptation" />
              <r-option label="前作/续作 (sequel)" value="sequel" />
              <r-option label="属于纪元/时间线 (belongs_to_era)" value="belongs_to_era" />
              <r-option label="制作公司 (studio)" value="studio" />
            </r-select>
            <r-input v-model="relationRoleDesc" placeholder="职能/角色说明 (如: 空我全形态皮套演职)" style="flex: 1;" />
            <r-button type="primary" :loading="savingRelation" @click="addRelation">添加关系</r-button>
          </div>
        </div>

        <!-- 正向关系 -->
        <div class="rel-section">
          <div class="section-badge-header">
            <h4>正向关联连线 (由此词条引申出)</h4>
            <span class="count-pill">{{ subjectDetail?.forward_relations?.length || 0 }} 条</span>
          </div>
          <r-table :data="subjectDetail?.forward_relations || []" border size="small" empty-text="暂无正向关联">
            <r-table-column label="关联目标" min-width="170">
              <template #default="{ row }">
                <strong class="rel-entity-title">{{ row.target_subject?.name }}</strong>
                <small class="rel-entity-sub">({{ subTypeLabels[row.target_subject?.sub_type] || row.target_subject?.type }})</small>
              </template>
            </r-table-column>
            <r-table-column label="关系属性" width="160">
              <template #default="{ row }">
                <r-tag size="small" type="primary">{{ relTypeLabels[row.relation_type] || row.relation_type }}</r-tag>
              </template>
            </r-table-column>
            <r-table-column prop="role_description" label="具体职能 / 饰演角色" min-width="210">
              <template #default="{ row }">
                <span class="role-desc-text">{{ row.role_description || '常规出演/任职' }}</span>
              </template>
            </r-table-column>
            <r-table-column label="操作" width="90" align="center">
              <template #default="{ row }">
                <r-button v-if="!readOnly" size="small" type="danger" link @click="removeRelation(row.id)">解除</r-button>
              </template>
            </r-table-column>
          </r-table>
        </div>

        <!-- 反向关系 -->
        <div class="rel-section" style="margin-top: 18px;">
          <div class="section-badge-header">
            <h4>反向被引连线 (其他词条挂载于此，如参演作品/被指派)</h4>
            <span class="count-pill">{{ subjectDetail?.reverse_relations?.length || 0 }} 条</span>
          </div>
          <r-table :data="subjectDetail?.reverse_relations || []" border size="small" empty-text="暂无反向引用">
            <r-table-column label="来源作品 / 实体" min-width="170">
              <template #default="{ row }">
                <strong class="rel-entity-title">{{ row.source_subject?.name }}</strong>
                <small class="rel-entity-sub">({{ subTypeLabels[row.source_subject?.sub_type] || row.source_subject?.type }})</small>
              </template>
            </r-table-column>
            <r-table-column label="被引身份" width="160">
              <template #default="{ row }">
                <r-tag size="small" type="info">{{ relTypeLabels[row.relation_type] || row.relation_type }}</r-tag>
              </template>
            </r-table-column>
            <r-table-column prop="role_description" label="具体职能 / 饰演角色" min-width="210">
              <template #default="{ row }">
                <span class="role-desc-text">{{ row.role_description || '常规出演/任职' }}</span>
              </template>
            </r-table-column>
            <r-table-column label="操作" width="90" align="center">
              <template #default="{ row }">
                <r-button v-if="!readOnly" size="small" type="danger" link @click="removeRelation(row.id)">解除</r-button>
              </template>
            </r-table-column>
          </r-table>
        </div>

        <!-- 关联播放源 -->
        <div v-if="subjectDetail?.linked_videos && subjectDetail.linked_videos.length" class="rel-section" style="margin-top: 18px;">
          <div class="section-badge-header">
            <h4>关联的线上播放视频</h4>
            <span class="count-pill success">{{ subjectDetail.linked_videos.length }} 部</span>
          </div>
          <div class="linked-videos-list">
            <div v-for="v in subjectDetail.linked_videos" :key="v.id" class="video-pill">
              <r-icon :size="14"><Film /></r-icon>
              <span class="vid-title">{{ v.name }}</span>
              <small class="vid-info">{{ v.year || '-' }} · {{ v.remarks || '在线' }}</small>
            </div>
          </div>
        </div>
      </div>
    </r-dialog>

    <!-- 3. 知识图谱全景拓扑弹窗 -->
    <r-dialog
      v-model="graphDialogVisible"
      :title="`知识图谱全景拓扑 · ${currentSubject?.name || ''}`"
      width="min(1080px, 96vw)"
      destroy-on-close
    >
      <div v-loading="graphLoading" class="graph-modal-container">
        <!-- 顶部中心实体全景看板 -->
        <div class="graph-hero-card">
          <div class="hero-left">
            <div class="hero-thumb">
              <img v-if="currentSubject?.cover_image" :src="currentSubject.cover_image" :alt="currentSubject.name" />
              <div v-else class="hero-thumb-placeholder" :class="currentSubject?.type">
                {{ currentSubject?.name ? currentSubject.name.slice(0, 1) : 'W' }}
              </div>
            </div>
            <div class="hero-info">
              <div class="hero-title-row">
                <h3 class="hero-title">{{ currentSubject?.name }}</h3>
                <r-tag size="small" :type="getTypeTag(currentSubject?.type)">{{ typeLabels[currentSubject?.type] }}</r-tag>
                <span class="hero-sub-type">{{ subTypeLabels[currentSubject?.sub_type] || currentSubject?.sub_type }}</span>
              </div>
              <p v-if="currentSubject?.original_name" class="hero-original-name">{{ currentSubject.original_name }}</p>
              <p class="hero-summary" v-if="currentSubject?.summary">{{ currentSubject.summary }}</p>
            </div>
          </div>
          <div class="hero-stats">
            <div class="stat-box">
              <span class="stat-num">{{ graphData?.nodes?.length || 0 }}</span>
              <span class="stat-lbl">直连实体</span>
            </div>
            <div class="stat-box accent">
              <span class="stat-num">{{ graphData?.edges?.length || 0 }}</span>
              <span class="stat-lbl">拓扑关系边</span>
            </div>
          </div>
        </div>

        <!-- 视角切换 -->
        <div class="graph-view-toolbar">
          <div class="view-switch-tabs">
            <button
              class="view-tab-btn"
              :class="{ active: graphViewMode === 'cards' }"
              @click="graphViewMode = 'cards'"
            >
              <r-icon :size="14"><Network /></r-icon> 演职星盘节点卡片 ({{ graphData?.nodes?.length || 0 }})
            </button>
            <button
              class="view-tab-btn"
              :class="{ active: graphViewMode === 'table' }"
              @click="graphViewMode = 'table'"
            >
              <r-icon :size="14"><Film /></r-icon> 拓扑路径连线矩阵 ({{ graphData?.edges?.length || 0 }})
            </button>
          </div>
          <span class="graph-tip">💡 提示：点击任意节点卡片可下钻漫游，切换为该节点的关联星盘</span>
        </div>

        <!-- 视角 1：实体节点卡片网格 -->
        <div v-show="graphViewMode === 'cards'" class="graph-cards-view">
          <div class="nodes-grid">
            <div
              v-for="node in graphData?.nodes"
              :key="node.id"
              class="node-card"
              :class="{ 'is-root': node.id === currentSubject?.id }"
              @click="switchGraphRoot(node)"
            >
              <div class="card-avatar" :class="node.sub_type || node.type">
                <span>{{ node.name.slice(0, 1) }}</span>
              </div>
              <div class="card-content">
                <div class="card-title-row">
                  <strong class="card-name" :title="node.name">{{ node.name }}</strong>
                  <span v-if="node.id === currentSubject?.id" class="root-badge">中心根</span>
                </div>
                <div class="card-meta">
                  <span class="meta-role">{{ subTypeLabels[node.sub_type] || typeLabels[node.type] || node.type }}</span>
                  <span v-if="getNodeRelationLabel(node.id)" class="meta-rel-pill">
                    {{ getNodeRelationLabel(node.id) }}
                  </span>
                </div>
              </div>
              <div class="card-hover-arrow">
                <r-icon :size="14"><Network /></r-icon>
              </div>
            </div>
          </div>
        </div>

        <!-- 视角 2：拓扑链路关系表 -->
        <div v-show="graphViewMode === 'table'" class="graph-table-view">
          <r-table :data="graphData?.edges || []" border size="small" stripe style="width: 100%;">
            <r-table-column label="起始实体 (Source)" min-width="190">
              <template #default="{ row }">
                <div class="table-entity-cell">
                  <r-icon :size="13"><Film /></r-icon>
                  <strong>{{ getNodeName(row.source) }}</strong>
                </div>
              </template>
            </r-table-column>
            <r-table-column label="定向拓扑连线" width="220" align="center">
              <template #default="{ row }">
                <div class="directed-edge-badge">
                  <span class="edge-line"></span>
                  <span class="edge-tag">{{ relTypeLabels[row.relation] || row.relation }}</span>
                  <span class="edge-arrow">➔</span>
                </div>
                <span v-if="row.role" class="edge-role-text">({{ row.role }})</span>
              </template>
            </r-table-column>
            <r-table-column label="目标实体 (Target)" min-width="190">
              <template #default="{ row }">
                <div class="table-entity-cell">
                  <span class="target-avatar-circle">{{ getNodeName(row.target).slice(0, 1) }}</span>
                  <strong>{{ getNodeName(row.target) }}</strong>
                </div>
              </template>
            </r-table-column>
            <r-table-column label="图谱漫游" width="110" align="center">
              <template #default="{ row }">
                <r-button size="small" type="primary" link @click="switchGraphRootById(row.target)">
                  漫游此节点
                </r-button>
              </template>
            </r-table-column>
          </r-table>
        </div>
      </div>
    </r-dialog>

    <!-- 4. 从视频库一键同步弹窗 -->
    <r-dialog
      v-model="syncDialogVisible"
      title="从视频库一键冷启动同步为 Wiki 图谱"
      width="520px"
    >
      <div class="sync-box">
        <p class="helper">输入视频库中的视频 ID，系统将自动读取片名创建作品词条，并智能拆解主演、导演等演职人员字符串，自动为每个人物建档并挂载演职关系。</p>
        <r-form label-width="100px">
          <r-form-item label="视频 ID" required>
            <r-input-number v-model="syncVideoId" :min="1" style="width: 100%;" placeholder="例如：1" />
          </r-form-item>
        </r-form>
      </div>
      <template #footer>
        <r-button @click="syncDialogVisible = false">取消</r-button>
        <r-button type="primary" :loading="syncing" @click="handleSyncVideo">开始一键同步</r-button>
      </template>
    </r-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, reactive, onMounted } from 'vue'
import { useUserStore } from '@/store/user'
import { Plus, RefreshCw, Film, Network, Search } from '@/components/radix/icons'
import { notify, confirmAction } from '@/components/radix/feedback'
import {
  getWikiSubjects,
  getWikiSubjectDetail,
  saveWikiSubject,
  deleteWikiSubject,
  createWikiRelation,
  deleteWikiRelation,
  getWikiGraph,
  syncVideoToWiki
} from '@/api/admin'

const userStore = useUserStore()
const readOnly = computed(() => userStore.userInfo?.role === 'observer')
const hasFilters = computed(() => Boolean(searchQuery.value.trim() || filterType.value || filterSubType.value))

const typeLabels: Record<string, string> = {
  work: '🎬 作品',
  person: '👤 人物',
  character: '🎭 角色',
  event: '⏳ 纪元',
  org: '🏢 机构'
}

const subTypeLabels: Record<string, string> = {
  tokusatsu: '特摄作品',
  suit_actor: '皮套演员',
  martial_arts: '动作监督/武指',
  cv: '声优/配音',
  actor: '演员',
  director: '导演',
  anime: '番剧动画',
  movie: '电影',
  tv: '电视剧',
  game: '电子游戏',
  era: '宇宙纪元',
  timeline: '编年史',
  studio: '制作工作室'
}

const relTypeLabels: Record<string, string> = {
  suit_actor: '皮套演职',
  action_director: '动作监督/武指',
  cv: '配音/声优',
  actor: '主演/出演',
  director: '导演',
  belongs_to_era: '属于纪元',
  game_adaptation: '衍生游戏',
  sequel: '后继作品',
  prequel: '前传作品',
  studio: '制作出品'
}

const getTypeTag = (type: string) => {
  switch (type) {
    case 'work': return 'primary'
    case 'person': return 'success'
    case 'character': return 'warning'
    case 'event': return 'danger'
    default: return 'info'
  }
}

// 辅助方法：限制 Infobox 展示条数
function getLimitedInfobox(infobox: Record<string, any>, limit: number) {
  const entries = Object.entries(infobox || {})
  const result: Record<string, any> = {}
  entries.slice(0, limit).forEach(([k, v]) => {
    result[k] = v
  })
  return result
}

function formatAllInfobox(infobox: Record<string, any>) {
  return Object.entries(infobox || {})
    .map(([k, v]) => `${k}: ${v}`)
    .join('\n')
}

// 列表数据与筛选
const loading = ref(false)
const tableData = ref<any[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const searchQuery = ref('')
const filterType = ref('')
const filterSubType = ref('')

// 编辑弹窗
const editDialogVisible = ref(false)
const editingId = ref<number | null>(null)
const submitting = ref(false)
const aliasesText = ref('')
const infoboxList = ref<{ key: string; value: string }[]>([])
const form = reactive({
  name: '',
  original_name: '',
  type: 'work',
  sub_type: 'movie',
  summary: '',
  cover_image: '',
  infobox: {} as Record<string, any>,
  aliases: [] as string[]
})

// 关系抽屉与详情
const relationsVisible = ref(false)
const relationsLoading = ref(false)
const currentSubject = ref<any>(null)
const subjectDetail = ref<any>(null)
const relationTargetName = ref('')
const relationType = ref('suit_actor')
const relationRoleDesc = ref('')
const savingRelation = ref(false)

// 图谱弹窗
const graphDialogVisible = ref(false)
const graphLoading = ref(false)
const graphData = ref<any>(null)
const graphViewMode = ref<'cards' | 'table'>('cards')

// 视频同步弹窗
const syncDialogVisible = ref(false)
const syncVideoId = ref<number | null>(null)
const syncing = ref(false)

async function loadData() {
  loading.value = true
  try {
    const res = await getWikiSubjects({
      page: page.value,
      page_size: pageSize.value,
      type: filterType.value || undefined,
      sub_type: filterSubType.value || undefined,
      keyword: searchQuery.value || undefined
    })
    tableData.value = res.data || []
    total.value = res.total || 0
  } finally {
    loading.value = false
  }
}

function handleSearch() {
  page.value = 1
  loadData()
}

function resetFilters() {
  searchQuery.value = ''
  filterType.value = ''
  filterSubType.value = ''
  page.value = 1
  loadData()
}

function openEditDialog(row?: any) {
  if (readOnly.value) return
  if (row) {
    editingId.value = row.id
    form.name = row.name || ''
    form.original_name = row.original_name || ''
    form.type = row.type || 'work'
    form.sub_type = row.sub_type || ''
    form.summary = row.summary || ''
    form.cover_image = row.cover_image || ''
    aliasesText.value = (row.aliases || []).join('\n')
    infoboxList.value = Object.entries(row.infobox || {}).map(([k, v]) => ({ key: k, value: String(v) }))
  } else {
    editingId.value = null
    form.name = ''
    form.original_name = ''
    form.type = 'work'
    form.sub_type = 'tokusatsu'
    form.summary = ''
    form.cover_image = ''
    aliasesText.value = ''
    infoboxList.value = [{ key: '', value: '' }]
  }
  editDialogVisible.value = true
}

async function submitSubject() {
  if (readOnly.value) return
  if (!form.name.trim()) {
    notify('词条主名称不能为空', 'warning')
    return
  }
  submitting.value = true
  try {
    const infoboxObj: Record<string, any> = {}
    infoboxList.value.forEach(item => {
      if (item.key.trim() && item.value.trim()) {
        infoboxObj[item.key.trim()] = item.value.trim()
      }
    })
    const aliasesArr = aliasesText.value.split('\n').map(s => s.trim()).filter(Boolean)

    await saveWikiSubject({
      id: editingId.value || undefined,
      name: form.name.trim(),
      original_name: form.original_name.trim(),
      type: form.type,
      sub_type: form.sub_type,
      summary: form.summary,
      cover_image: form.cover_image.trim(),
      infobox: infoboxObj,
      aliases: aliasesArr
    })
    notify(editingId.value ? '词条修改已保存' : '新词条已创建', 'success')
    editDialogVisible.value = false
    loadData()
  } finally {
    submitting.value = false
  }
}

async function handleDelete(row: any) {
  if (readOnly.value) return
  try {
    await confirmAction(`确定彻底删除词条【${row.name}】吗？删除后相关关联关系将同步解除。`, '确认删除', {
      type: 'danger',
      confirmButtonText: '删除',
      cancelButtonText: '取消'
    })
    await deleteWikiSubject(row.id)
    notify('词条已成功删除', 'success')
    loadData()
  } catch {}
}

async function openRelationsDialog(row: any) {
  currentSubject.value = row
  relationsVisible.value = true
  relationTargetName.value = ''
  relationRoleDesc.value = ''
  await loadSubjectDetail(row.id)
}

async function loadSubjectDetail(id: number) {
  relationsLoading.value = true
  try {
    const res = await getWikiSubjectDetail(id)
    subjectDetail.value = res.data
  } finally {
    relationsLoading.value = false
  }
}

async function addRelation() {
  if (readOnly.value) return
  if (!relationTargetName.value.trim()) {
    notify('请输入目标词条名称', 'warning')
    return
  }
  savingRelation.value = true
  try {
    const searchRes = await getWikiSubjects({ keyword: relationTargetName.value.trim() })
    let targetSub = (searchRes.data || []).find((s: any) => s.name === relationTargetName.value.trim())
    if (!targetSub) {
      const targetType = ['suit_actor', 'action_director', 'cv', 'actor', 'director'].includes(relationType.value) ? 'person' : 'work'
      const created = await saveWikiSubject({
        name: relationTargetName.value.trim(),
        type: targetType,
        sub_type: relationType.value
      })
      const newId = (created as any).data?.id || (created as any).id
      targetSub = { id: newId, name: relationTargetName.value.trim() }
    }

    await createWikiRelation({
      source_id: currentSubject.value.id,
      target_id: targetSub.id,
      relation_type: relationType.value,
      role_description: relationRoleDesc.value.trim()
    })
    notify('关联连线已成功建立', 'success')
    relationTargetName.value = ''
    relationRoleDesc.value = ''
    await loadSubjectDetail(currentSubject.value.id)
  } finally {
    savingRelation.value = false
  }
}

async function removeRelation(relId: number) {
  if (readOnly.value) return
  try {
    await deleteWikiRelation(relId)
    notify('关系已解除', 'success')
    await loadSubjectDetail(currentSubject.value.id)
  } catch {}
}

async function openGraphDialog(row: any) {
  currentSubject.value = row
  graphDialogVisible.value = true
  graphLoading.value = true
  graphViewMode.value = 'cards'
  try {
    const res = await getWikiGraph(row.id, 1)
    graphData.value = res.data
  } finally {
    graphLoading.value = false
  }
}

function getNodeRelationLabel(nodeId: number): string {
  if (!graphData.value || !graphData.value.edges) return ''
  const edge = graphData.value.edges.find((e: any) => e.target === nodeId || e.source === nodeId)
  if (!edge) return ''
  return relTypeLabels[edge.relation] || edge.relation
}

function switchGraphRoot(node: any) {
  if (node.id === currentSubject.value?.id) return
  openGraphDialog(node)
}

function switchGraphRootById(id: number) {
  const node = (graphData.value?.nodes || []).find((n: any) => n.id === id)
  if (node) {
    switchGraphRoot(node)
  }
}

function getNodeName(id: number) {
  const node = (graphData.value?.nodes || []).find((n: any) => n.id === id)
  return node ? `${node.name} (${subTypeLabels[node.sub_type] || node.type})` : `实体 #${id}`
}

function openSyncDialog() {
  if (readOnly.value) return
  syncVideoId.value = null
  syncDialogVisible.value = true
}

async function handleSyncVideo() {
  if (readOnly.value) return
  if (!syncVideoId.value || syncVideoId.value <= 0) {
    notify('请输入合法的视频 ID', 'warning')
    return
  }
  syncing.value = true
  try {
    const res = await syncVideoToWiki(syncVideoId.value)
    notify(`已成功为《${res.data?.subject?.name || ''}》建立 Wiki 实体与演职关系网！`, 'success')
    syncDialogVisible.value = false
    loadData()
  } finally {
    syncing.value = false
  }
}

onMounted(() => {
  loadData()
})
</script>

<style scoped lang="scss">
.usage-guide {
  margin-bottom: 14px;
  font-size: 12px;

  ol { margin: 0; padding-left: 20px; line-height: 1.8; color: var(--text-secondary); }
}
.empty-actions { display: flex; gap: 8px; flex-wrap: wrap; justify-content: center; }

.wiki-page {
  padding: 16px;
  min-height: 100%;

  .table-card {
    border-radius: var(--radius-md);
  }

  .wiki-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 16px;
    margin-bottom: 16px;
    padding-bottom: 14px;
    border-bottom: 1px solid var(--border-color);

    .eyebrow {
      font-size: 9.5px;
      letter-spacing: 1.5px;
      font-weight: 700;
      color: var(--brand);
      text-transform: uppercase;
      display: block;
      margin-bottom: 2px;
    }

    .title-row {
      display: flex;
      align-items: center;
      gap: 12px;
      flex-wrap: wrap;

      .page-title {
        font-size: 17px;
        font-weight: 700;
        color: var(--text-primary);
        margin: 0;
      }

      .stats-pills {
        display: flex;
        gap: 6px;
        align-items: center;

        .stat-pill {
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

          &.primary {
            background: rgba(99, 102, 241, 0.1);
            color: var(--brand);
          }
        }
      }
    }

    .sub-desc {
      font-size: 11.5px;
      color: var(--text-secondary);
      margin: 4px 0 0 0;
    }

    .header-right {
      display: flex;
      gap: 8px;
      flex-shrink: 0;
    }
  }

  .filter-bar {
    display: flex;
    gap: 10px;
    align-items: center;
    margin-bottom: 16px;
    flex-wrap: wrap;
    background: var(--bg-hover, rgba(248, 250, 252, 0.6));
    padding: 10px 12px;
    border-radius: var(--radius-sm, 6px);
    border: 1px solid var(--border-color);

    .search-input-wrap {
      flex: 1;
      min-width: 240px;
    }

    .filter-actions {
      display: flex;
      gap: 8px;
    }
  }

  .cell-id {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 11px;
    color: var(--text-secondary);
  }

  .cover-wrapper {
    display: flex;
    align-items: center;
    justify-content: center;

    .table-cover {
      width: 44px;
      height: 60px;
      object-fit: cover;
      border-radius: 6px;
      border: 1px solid var(--border-color);
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
      background: var(--bg-hover, #f1f5f9);
    }

    .cover-placeholder {
      width: 44px;
      height: 60px;
      border-radius: 6px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-weight: 700;
      font-size: 16px;
      border: 1px dashed var(--border-color);
      background: var(--bg-hover, #f8fafc);
      color: var(--text-secondary);

      &.work { background: rgba(59, 130, 246, 0.08); color: #3b82f6; }
      &.person { background: rgba(16, 185, 129, 0.08); color: #10b981; }
      &.character { background: rgba(245, 158, 11, 0.08); color: #f59e0b; }
      &.event { background: rgba(239, 68, 68, 0.08); color: #ef4444; }
    }
  }

  .name-cell {
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;

    .main-name {
      font-size: 13.5px;
      font-weight: 600;
      color: var(--text-primary);
      line-height: 1.3;
    }

    .sub-name {
      color: var(--text-secondary);
      font-size: 11px;
      line-height: 1.3;
      max-width: 250px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      display: block;
    }

    .alias-chips {
      display: flex;
      gap: 4px;
      margin-top: 2px;
      flex-wrap: nowrap;
      overflow: hidden;
      max-width: 250px;

      .alias-chip {
        font-size: 10px;
        padding: 1px 5px;
        border-radius: 3px;
        background: rgba(100, 116, 139, 0.1);
        color: var(--text-secondary);
        white-space: nowrap;
        max-width: 105px;
        overflow: hidden;
        text-overflow: ellipsis;
        flex-shrink: 0;

        &.more {
          background: rgba(99, 102, 241, 0.1);
          color: var(--brand);
          flex-shrink: 0;
        }
      }
    }
  }

  .type-cell {
    display: inline-flex;
    flex-direction: column;
    gap: 4px;
    align-items: center;
    justify-content: center;
    white-space: nowrap;
    width: 100%;

    .r-tag {
      white-space: nowrap;
      flex-shrink: 0;
    }

    .sub-type-badge {
      font-size: 11px;
      color: var(--text-secondary);
      background: rgba(100, 116, 139, 0.08);
      padding: 1px 6px;
      border-radius: 4px;
      display: inline-block;
      white-space: nowrap;
    }
  }

  .infobox-preview {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    align-items: center;
    max-height: 52px;
    overflow: hidden;

    .infobox-pill {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      font-size: 11px;
      background: rgba(100, 116, 139, 0.09);
      border: 1px solid rgba(148, 163, 184, 0.2);
      padding: 1px 6px;
      border-radius: 4px;
      color: var(--text-secondary);
      white-space: nowrap;
      flex-shrink: 0;

      .pill-k {
        font-weight: 600;
        color: var(--text-primary);
        white-space: nowrap;
      }
      .pill-v {
        max-width: 85px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    .infobox-more {
      font-size: 10.5px;
      color: var(--brand);
      cursor: pointer;
      padding: 1px 5px;
      background: rgba(99, 102, 241, 0.08);
      border-radius: 3px;
      white-space: nowrap;
      flex-shrink: 0;
    }
  }

  .text-muted-empty {
    font-size: 11px;
    color: #94a3b8;
  }

  .cell-summary {
    margin: 0;
    font-size: 11.5px;
    line-height: 1.45;
    color: var(--text-secondary);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    word-break: break-all;
  }

  .table-actions-row {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    white-space: nowrap;
    flex-wrap: nowrap;

    .r-button {
      white-space: nowrap;
      flex-shrink: 0;
      padding: 0.25rem 0.5rem;
      font-size: 12px;
      gap: 3px;
    }

    .rel-badge {
      background: rgba(59, 130, 246, 0.15);
      color: #3b82f6;
      font-weight: 700;
      padding: 0 4px;
      border-radius: 9999px;
      font-size: 10px;
      margin-left: 2px;
    }
  }

  .pagination-bar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 16px;
    padding-top: 10px;
    border-top: 1px solid var(--border-color);

    .total-indicator {
      font-size: 12px;
      color: var(--text-secondary);

      strong {
        color: var(--text-primary);
      }
    }
  }
}
</style>

<!-- 独立顶层样式：专门作用于被 Teleport 传送至 document.body 的各种弹窗内容 -->
<style lang="scss">
.relation-guide { font-size: 12px; line-height: 1.7; color: var(--text-secondary); }

/* 1. 词条编辑弹窗内部 */
.wiki-form {
  .form-row-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
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

  .infobox-editor {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 6px;

    .editor-tip {
      font-size: 11px;
      color: var(--text-secondary);
      margin: 0 0 4px 0;
    }

    .infobox-row {
      display: flex;
      gap: 8px;
      align-items: center;
    }
  }
}

/* 2. 关系网弹窗内部 */
.relations-box {
  .subject-brief-card {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px;
    background: var(--bg-hover, #f8fafc);
    border-radius: var(--radius-md, 8px);
    border: 1px solid var(--border-color);
    margin-bottom: 16px;

    .brief-thumb {
      width: 44px;
      height: 58px;
      border-radius: 6px;
      overflow: hidden;
      border: 1px solid var(--border-color);
      background: #fff;
      flex-shrink: 0;

      img { width: 100%; height: 100%; object-fit: cover; }
      .brief-thumb-empty {
        width: 100%; height: 100%; display: flex; align-items: center; justify-content: center;
        font-weight: 700; color: #94a3b8; font-size: 18px;
      }
    }

    .brief-meta {
      display: flex;
      flex-direction: column;
      gap: 4px;

      .brief-name {
        display: flex;
        align-items: baseline;
        gap: 8px;

        h3 { margin: 0; font-size: 15px; font-weight: 700; color: var(--text-primary); }
        small { color: var(--text-secondary); font-size: 12px; }
      }

      .brief-tags {
        display: flex;
        gap: 6px;
        align-items: center;

        .sub-badge {
          font-size: 11px;
          color: var(--text-secondary);
          background: rgba(100, 116, 139, 0.12);
          padding: 1px 6px;
          border-radius: 4px;
        }
      }
    }
  }

  .relation-add-bar {
    background: var(--card-bg, #fff);
    padding: 12px 14px;
    border-radius: var(--radius-md, 8px);
    margin-bottom: 16px;
    border: 1px solid var(--border-color);

    .add-bar-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 10px;

      h4 { margin: 0; font-size: 13px; font-weight: 700; color: var(--text-primary); }
      .sub-note { font-size: 11px; color: var(--text-secondary); }
    }

    .relation-form-row {
      display: flex;
      gap: 8px;
      align-items: center;
    }
  }

  .rel-section {
    .section-badge-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 8px;

      h4 { margin: 0; font-size: 13px; font-weight: 700; color: var(--text-primary); }
      .count-pill {
        font-size: 11px;
        padding: 1px 6px;
        background: rgba(100, 116, 139, 0.1);
        color: var(--text-secondary);
        border-radius: 9999px;

        &.success { background: rgba(16, 185, 129, 0.12); color: #10b981; }
      }
    }

    .rel-entity-title { color: var(--text-primary); }
    .rel-entity-sub { color: var(--text-secondary); margin-left: 6px; font-size: 11px; }
    .role-desc-text { font-size: 11.5px; color: var(--text-regular); }
  }

  .linked-videos-list {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;

    .video-pill {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 6px 12px;
      background: var(--bg-hover, #f1f5f9);
      border: 1px solid var(--border-color);
      border-radius: 6px;
      font-size: 12px;

      .vid-title { font-weight: 600; color: var(--text-primary); }
      .vid-info { color: var(--text-secondary); font-size: 11px; }
    }
  }
}

/* 3. 知识图谱拓扑全景弹窗内部 (彻底修复无样式垂直堆叠问题) */
.graph-modal-container {
  display: flex;
  flex-direction: column;
  gap: 14px;
  min-height: 480px;

  .graph-hero-card {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 16px;
    padding: 14px 18px;
    background: linear-gradient(135deg, rgba(99, 102, 241, 0.08) 0%, rgba(59, 130, 246, 0.04) 100%);
    border: 1px solid rgba(99, 102, 241, 0.22);
    border-radius: 10px;

    .hero-left {
      display: flex;
      gap: 14px;
      align-items: center;
      min-width: 0;
      flex: 1;

      .hero-thumb {
        width: 52px;
        height: 72px;
        border-radius: 6px;
        overflow: hidden;
        border: 1px solid var(--border-color);
        box-shadow: 0 2px 6px rgba(0, 0, 0, 0.1);
        flex-shrink: 0;

        img { width: 100%; height: 100%; object-fit: cover; }
        .hero-thumb-placeholder {
          width: 100%; height: 100%;
          display: flex; align-items: center; justify-content: center;
          font-weight: 700; font-size: 20px;
          background: #e0e7ff; color: #4338ca;
        }
      }

      .hero-info {
        display: flex;
        flex-direction: column;
        gap: 3px;
        min-width: 0;

        .hero-title-row {
          display: flex;
          align-items: center;
          gap: 8px;
          flex-wrap: wrap;

          .hero-title {
            margin: 0;
            font-size: 16px;
            font-weight: 700;
            color: var(--text-primary);
          }

          .hero-sub-type {
            font-size: 11px;
            background: rgba(100, 116, 139, 0.12);
            color: var(--text-secondary);
            padding: 1px 7px;
            border-radius: 4px;
          }
        }

        .hero-original-name {
          margin: 0;
          font-size: 12px;
          color: var(--text-secondary);
        }

        .hero-summary {
          margin: 2px 0 0 0;
          font-size: 11.5px;
          line-height: 1.4;
          color: var(--text-regular);
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
      }
    }

    .hero-stats {
      display: flex;
      gap: 12px;
      flex-shrink: 0;

      .stat-box {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        padding: 8px 16px;
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.85);
        border: 1px solid var(--border-color);
        min-width: 80px;

        .stat-num {
          font-size: 18px;
          font-weight: 700;
          color: var(--text-primary);
        }
        .stat-lbl {
          font-size: 10.5px;
          color: var(--text-secondary);
        }

        &.accent {
          background: rgba(99, 102, 241, 0.12);
          border-color: rgba(99, 102, 241, 0.3);
          .stat-num { color: var(--brand, #4f46e5); }
        }
      }
    }
  }

  .graph-view-toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;

    .view-switch-tabs {
      display: flex;
      gap: 6px;

      .view-tab-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 12px;
        font-weight: 600;
        padding: 6px 14px;
        border-radius: 6px;
        border: 1px solid var(--border-color);
        background: var(--card-bg, #fff);
        color: var(--text-secondary);
        cursor: pointer;
        transition: all 0.15s ease;

        &:hover {
          background: var(--bg-hover, #f8fafc);
          color: var(--text-primary);
        }

        &.active {
          background: var(--brand, #4f46e5);
          color: #fff;
          border-color: var(--brand, #4f46e5);
        }
      }
    }

    .graph-tip {
      font-size: 11.5px;
      color: #64748b;
    }
  }

  .graph-cards-view {
    .nodes-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
      gap: 10px;
      max-height: 460px;
      overflow-y: auto;
      padding: 2px;

      .node-card {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 12px;
        background: var(--card-bg, #fff);
        border: 1px solid var(--border-color);
        border-radius: 8px;
        cursor: pointer;
        transition: all 0.18s ease;
        position: relative;

        &:hover {
          border-color: var(--brand, #4f46e5);
          box-shadow: 0 4px 12px rgba(99, 102, 241, 0.12);
          transform: translateY(-1px);

          .card-hover-arrow {
            opacity: 1;
            color: var(--brand, #4f46e5);
          }
        }

        &.is-root {
          background: rgba(99, 102, 241, 0.08);
          border-color: var(--brand, #4f46e5);
          box-shadow: 0 0 0 1px var(--brand, #4f46e5);
        }

        .card-avatar {
          width: 38px;
          height: 38px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-weight: 700;
          font-size: 15px;
          color: #fff;
          background: #64748b;
          flex-shrink: 0;

          &.director { background: #8b5cf6; }
          &.actor { background: #10b981; }
          &.cv { background: #f59e0b; }
          &.suit_actor { background: #f43f5e; }
          &.tokusatsu { background: #3b82f6; }
          &.anime { background: #06b6d4; }
        }

        .card-content {
          display: flex;
          flex-direction: column;
          gap: 3px;
          min-width: 0;
          flex: 1;

          .card-title-row {
            display: flex;
            align-items: center;
            gap: 4px;

            .card-name {
              font-size: 13px;
              color: var(--text-primary);
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }

            .root-badge {
              font-size: 9.5px;
              background: var(--brand, #4f46e5);
              color: #fff;
              padding: 0 4px;
              border-radius: 3px;
              flex-shrink: 0;
            }
          }

          .card-meta {
            display: flex;
            align-items: center;
            gap: 6px;

            .meta-role {
              font-size: 11px;
              color: var(--text-secondary);
            }

            .meta-rel-pill {
              font-size: 10px;
              padding: 0 4px;
              border-radius: 3px;
              background: rgba(99, 102, 241, 0.1);
              color: var(--brand, #4f46e5);
            }
          }
        }

        .card-hover-arrow {
          opacity: 0.2;
          transition: opacity 0.15s ease;
          flex-shrink: 0;
        }
      }
    }
  }

  .graph-table-view {
    .table-entity-cell {
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 12.5px;

      strong { color: var(--text-primary); }
      .target-avatar-circle {
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: #e2e8f0;
        color: #475569;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-size: 11px;
        font-weight: 700;
      }
    }

    .directed-edge-badge {
      display: inline-flex;
      align-items: center;
      gap: 4px;

      .edge-line {
        display: inline-block;
        width: 18px;
        height: 1px;
        background: #cbd5e1;
      }

      .edge-tag {
        font-size: 11px;
        font-weight: 600;
        padding: 2px 8px;
        background: rgba(16, 185, 129, 0.1);
        color: #059669;
        border-radius: 9999px;
        border: 1px solid rgba(16, 185, 129, 0.25);
      }

      .edge-arrow {
        color: #059669;
        font-size: 12px;
      }
    }

    .edge-role-text {
      display: block;
      font-size: 11px;
      color: var(--text-secondary);
      margin-top: 2px;
    }
  }
}

/* 4. 同步弹窗内部 */
.sync-box {
  padding: 6px 0;

  .helper {
    font-size: 12px;
    color: var(--text-secondary);
    line-height: 1.6;
    margin-bottom: 16px;
  }
}
</style>
