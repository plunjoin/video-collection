package maccms

import (
	"testing"
)

func TestParseMacCmsXml(t *testing.T) {
	xmlData := []byte(`<?xml version="1.0" encoding="utf-8"?>
<rss version="5.1">
  <class>
    <ty id="1">电影</ty>
    <ty id="2">连续剧</ty>
  </class>
  <list page="1" pagecount="5" pagesize="20" recordcount="100">
    <video>
      <last>2026-09-26 12:00:00</last>
      <id>9991</id>
      <tid>1</tid>
      <name><![CDATA[流浪地球3]]></name>
      <type>科幻片</type>
      <pic>https://example.com/poster.jpg</pic>
      <lang>国语</lang>
      <area>大陆</area>
      <year>2027</year>
      <state>预告片</state>
      <note><![CDATA[先行预告]]></note>
      <actor><![CDATA[吴京,刘德华]]></actor>
      <director><![CDATA[郭帆]]></director>
      <des><![CDATA[太阳危机再次降临...]]></des>
      <dl>
        <dd flag="m3u8"><![CDATA[第01集$https://cdn.example.com/ep1.m3u8#第02集$https://cdn.example.com/ep2.m3u8]]></dd>
        <dd flag="kkm3u8"><![CDATA[第01集$https://backup.example.com/ep1.m3u8]]></dd>
      </dl>
    </video>
  </list>
</rss>`)

	resp, err := ParseXmlResponse(xmlData)
	if err != nil {
		t.Fatalf("ParseXmlResponse failed: %v", err)
	}

	if len(resp.Class) != 2 {
		t.Fatalf("expected 2 classes, got %d", len(resp.Class))
	}
	if len(resp.List) != 1 {
		t.Fatalf("expected 1 video, got %d", len(resp.List))
	}

	vod := resp.List[0]
	if vod.VodName != "流浪地球3" {
		t.Errorf("expected name 流浪地球3, got %s", vod.VodName)
	}
	if vod.VodID.Int() != 9991 {
		t.Errorf("expected id 9991, got %d", vod.VodID.Int())
	}
	if vod.VodPlayFrom != "m3u8$$$kkm3u8" {
		t.Errorf("expected play from m3u8$$$kkm3u8, got %s", vod.VodPlayFrom)
	}
}

func TestParseRss2Feed(t *testing.T) {
	rssData := []byte(`<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0">
  <channel>
    <title>测试视频订阅</title>
    <link>https://example.com</link>
    <item>
      <title>科技前沿播客第一期</title>
      <link>https://example.com/video/1</link>
      <category>科技</category>
      <pubDate>Sat, 26 Sep 2026 12:00:00 GMT</pubDate>
      <description><![CDATA[<img src="https://example.com/thumb.jpg" /> 本期带来最新的科技新闻。]]></description>
      <enclosure url="https://example.com/video.mp4" type="video/mp4" />
    </item>
  </channel>
</rss>`)

	resp, err := ParseXmlResponse(rssData)
	if err != nil {
		t.Fatalf("ParseXmlResponse failed: %v", err)
	}

	if len(resp.List) != 1 {
		t.Fatalf("expected 1 item, got %d", len(resp.List))
	}

	item := resp.List[0]
	if item.VodName != "科技前沿播客第一期" {
		t.Errorf("unexpected name: %s", item.VodName)
	}
	if item.VodPic != "https://example.com/thumb.jpg" {
		t.Errorf("unexpected pic: %s", item.VodPic)
	}
	if item.VodPlayURL != "第01集$https://example.com/video.mp4" {
		t.Errorf("unexpected play url: %s", item.VodPlayURL)
	}
}
