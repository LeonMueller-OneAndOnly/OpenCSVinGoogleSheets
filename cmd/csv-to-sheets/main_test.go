package main

import "testing"

func TestGoogleContentType(t *testing.T) {
	if got := googleContentType("report.TSV"); got != "text/tab-separated-values" {
		t.Fatalf("googleContentType TSV = %q", got)
	}
	if got := googleContentType("report.csv"); got != "text/csv" {
		t.Fatalf("googleContentType CSV = %q", got)
	}
	if got := googleContentType("report.xlsx"); got != "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" {
		t.Fatalf("googleContentType XLSX = %q", got)
	}
}

func TestEscapeAppleScript(t *testing.T) {
	got := escapeAppleScript("A \"quote\"\\next")
	want := `A \"quote\"\\next`
	if got != want {
		t.Fatalf("escapeAppleScript = %q, want %q", got, want)
	}
}
