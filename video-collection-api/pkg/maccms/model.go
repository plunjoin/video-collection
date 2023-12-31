package maccms

import (
	"fmt"
	"strconv"
	"strings"
)

// FlexInt 兼容 JSON 反序列化中数字与数字字符串（如 123 和 "123"）
type FlexInt int

func (fi *FlexInt) UnmarshalJSON(b []byte) error {
	str := strings.Trim(string(b), "\"")
	if str == "" || str == "null" {
		*fi = 0
		return nil
	}
	val, err := strconv.Atoi(str)
	if err != nil {
		// 尝试解析 float
		fVal, fErr := strconv.ParseFloat(str, 64)
		if fErr != nil {
			return fmt.Errorf("cannot unmarshal %s into FlexInt: %w", string(b), err)
		}
		*fi = FlexInt(int(fVal))
		return nil
	}
	*fi = FlexInt(val)
	return nil
}

func (fi FlexInt) Int() int {
	return int(fi)
}

// MacCmsResponse MacCMS v10 标准接口响应格式
type MacCmsResponse struct {
	Code      FlexInt     `json:"code"`
	Msg       string      `json:"msg"`
	Page      FlexInt     `json:"page"`
	PageCount FlexInt     `json:"pagecount"`
	Limit     FlexInt     `json:"limit"`
	Total     FlexInt     `json:"total"`
	List      []VodItem   `json:"list"`
	Class     []ClassItem `json:"class"`
}

// ClassItem 采集源的分类定义
type ClassItem struct {
	TypeID   FlexInt `json:"type_id"`
	TypePID  FlexInt `json:"type_pid"`
	TypeName string  `json:"type_name"`
}

// VodItem 苹果CMS v10 视频原始条目结构
type VodItem struct {
	VodID        FlexInt `json:"vod_id"`
	VodName      string  `json:"vod_name"`
	VodSub       string  `json:"vod_sub"`
	VodEn        string  `json:"vod_en"`
	VodStatus    FlexInt `json:"vod_status"`
	VodTag       string  `json:"vod_tag"`
	TypeID       FlexInt `json:"type_id"`
	TypeName     string  `json:"type_name"`
	VodTime      string  `json:"vod_time"`
	VodRemarks   string  `json:"vod_remarks"`
	VodPlayFrom  string  `json:"vod_play_from"`
	VodPlayServer string `json:"vod_play_server"`
	VodPlayNote  string  `json:"vod_play_note"`
	VodPlayURL   string  `json:"vod_play_url"`
	VodDownFrom  string  `json:"vod_down_from"`
	VodDownURL   string  `json:"vod_down_url"`
	VodPic       string  `json:"vod_pic"`
	VodPicThumb  string  `json:"vod_pic_thumb"`
	VodActor     string  `json:"vod_actor"`
	VodDirector  string  `json:"vod_director"`
	VodWriter    string  `json:"vod_writer"`
	VodBlurb     string  `json:"vod_blurb"`
	VodPubDate   string  `json:"vod_pubdate"`
	VodTotal     FlexInt `json:"vod_total"`
	VodSerial    string  `json:"vod_serial"`
	VodArea      string  `json:"vod_area"`
	VodLang      string  `json:"vod_lang"`
	VodYear      string  `json:"vod_year"`
	VodState     string  `json:"vod_state"`
	VodScore     string  `json:"vod_score"`
	VodContent   string  `json:"vod_content"`
}

// Episode 单集结构
type Episode struct {
	Name string `json:"name"` // 集数名称，例如 "第01集"
	URL  string `json:"url"`  // 播放链接，例如 "https://xxx.m3u8"
}

// PlayGroup 播放源分组（支持多采集点节点独立标识）
type PlayGroup struct {
	SourceID   string    `json:"source_id,omitempty"`   // 来源采集节点ID，如 example_json
	SourceName string    `json:"source_name,omitempty"` // 来源采集节点名称，如 示例数据源
	PlayerCode string    `json:"player_code"`          // 播放器标识，如 m3u8, kkm3u8
	From       string    `json:"from,omitempty"`       // 兼容 Admin 前端 from 字段
	Server     string    `json:"server"`               // 服务器标识
	Note       string    `json:"note"`                 // 备注信息
	Episodes   []Episode `json:"episodes"`             // 包含的所有剧集列表
}

// CleanedVod 经过规则清洗和结构化解析后的标准视频对象
type CleanedVod struct {
	OriginalID     int         `json:"original_id"`
	SourceID       string      `json:"source_id,omitempty"`
	SourceName     string      `json:"source_name,omitempty"`
	Name           string      `json:"name"`
	SubName        string      `json:"sub_name"`
	TargetTypeID   int         `json:"target_type_id"`
	TargetTypeName string      `json:"target_type_name"`
	SourceTypeName string      `json:"source_type_name"`
	Picture        string      `json:"picture"`
	Actor          string      `json:"actor"`
	Director       string      `json:"director"`
	Area           string      `json:"area"`
	Language       string      `json:"language"`
	Year           string      `json:"year"`
	Remarks        string      `json:"remarks"`
	Content        string      `json:"content"`
	UpdateTime     string      `json:"update_time"`
	PlayGroups     []PlayGroup `json:"play_groups"`
}
