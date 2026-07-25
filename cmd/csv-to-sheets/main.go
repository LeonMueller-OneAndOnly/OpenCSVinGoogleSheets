package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/drive/v3"
	"google.golang.org/api/googleapi"
	"google.golang.org/api/option"
)

const (
	appName           = "CSVtoSheets"
	credentialsEnv    = "CSV_TO_SHEETS_CREDENTIALS"
	credentialsName   = "credentials.json"
	googleSheetsMIME  = "application/vnd.google-apps.spreadsheet"
	googleFolderMIME  = "application/vnd.google-apps.folder"
	defaultFolderName = "Sheets"
)

func main() {
	if err := run(context.Background(), os.Args[1:], os.Stdout); err != nil {
		showError(err)
		os.Exit(1)
	}
}

func run(ctx context.Context, paths []string, output io.Writer) error {
	if len(paths) == 0 {
		return errors.New("keine CSV-, TSV- oder XLSX-Datei angegeben")
	}

	for _, path := range paths {
		if err := validateInput(path); err != nil {
			return err
		}
	}

	config, err := loadOAuthConfig()
	if err != nil {
		return err
	}
	token, err := loadToken(config)
	if err != nil {
		return err
	}
	client := config.Client(ctx, token)
	service, err := drive.NewService(ctx, option.WithHTTPClient(client))
	if err != nil {
		return fmt.Errorf("Google Drive konnte nicht initialisiert werden: %w", err)
	}
	folderID, err := ensureDefaultFolder(service)
	if err != nil {
		return err
	}

	for _, path := range paths {
		fmt.Fprintf(output, "Lade %s hoch ...\n", filepath.Base(path))
		url, err := uploadAsSpreadsheet(service, path, folderID)
		if err != nil {
			return err
		}
		if err := openBrowser(url); err != nil {
			return fmt.Errorf("Google Sheet wurde erstellt, konnte aber nicht im Browser geöffnet werden: %w\n%s", err, url)
		}
		fmt.Fprintf(output, "Fertig: %s\n", url)
	}

	return nil
}

func validateInput(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("Datei kann nicht geöffnet werden (%s): %w", path, err)
	}
	if info.IsDir() {
		return fmt.Errorf("%s ist ein Ordner, keine unterstützte Datei", path)
	}
	if info.Size() == 0 {
		return fmt.Errorf("%s ist leer", filepath.Base(path))
	}
	extension := strings.ToLower(filepath.Ext(path))
	if extension != ".csv" && extension != ".tsv" && extension != ".xlsx" {
		return fmt.Errorf("%s wird nicht unterstützt; erlaubt sind .csv, .tsv und .xlsx", filepath.Base(path))
	}
	return nil
}

func loadOAuthConfig() (*oauth2.Config, error) {
	credentialsPath, err := credentialsPath()
	if err != nil {
		return nil, err
	}
	contents, err := os.ReadFile(credentialsPath)
	if err != nil {
		return nil, fmt.Errorf("Google-OAuth-Zugangsdaten fehlen. Lege %s neben die App oder setze %s: %w", credentialsName, credentialsEnv, err)
	}
	config, err := google.ConfigFromJSON(contents, drive.DriveFileScope)
	if err != nil {
		return nil, fmt.Errorf("ungültige Google-OAuth-Zugangsdaten: %w", err)
	}
	return config, nil
}

func credentialsPath() (string, error) {
	if path := os.Getenv(credentialsEnv); path != "" {
		return path, nil
	}
	executable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("Programmpfad konnte nicht bestimmt werden: %w", err)
	}
	candidates := []string{
		filepath.Join(filepath.Dir(executable), credentialsName),
		filepath.Join(filepath.Dir(executable), "..", "Resources", credentialsName),
	}
	for _, path := range candidates {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}
	return candidates[0], nil
}

func loadToken(config *oauth2.Config) (*oauth2.Token, error) {
	path, err := tokenPath()
	if err != nil {
		return nil, err
	}
	if contents, err := os.ReadFile(path); err == nil {
		var token oauth2.Token
		if err := json.Unmarshal(contents, &token); err == nil && token.Valid() {
			return &token, nil
		}
	}

	token, err := authorize(config)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, fmt.Errorf("Token-Ordner konnte nicht erstellt werden: %w", err)
	}
	contents, err := json.Marshal(token)
	if err != nil {
		return nil, fmt.Errorf("Token konnte nicht gespeichert werden: %w", err)
	}
	if err := os.WriteFile(path, contents, 0600); err != nil {
		return nil, fmt.Errorf("Token konnte nicht gespeichert werden: %w", err)
	}
	return token, nil
}

func tokenPath() (string, error) {
	directory, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("Konfigurationsordner konnte nicht bestimmt werden: %w", err)
	}
	return filepath.Join(directory, appName, "token.json"), nil
}

func authorize(config *oauth2.Config) (*oauth2.Token, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, fmt.Errorf("lokaler OAuth-Callback konnte nicht gestartet werden: %w", err)
	}
	defer listener.Close()

	config.RedirectURL = "http://" + listener.Addr().String()
	state := fmt.Sprintf("csv-to-sheets-%d", time.Now().UnixNano())
	authURL := config.AuthCodeURL(state, oauth2.AccessTypeOffline)
	if err := openBrowser(authURL); err != nil {
		return nil, fmt.Errorf("Google-Anmeldung konnte nicht im Browser geöffnet werden: %w", err)
	}

	result := make(chan struct {
		code string
		err  error
	}, 1)
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
		if request.URL.Query().Get("state") != state {
			result <- struct {
				code string
				err  error
			}{"", errors.New("OAuth-Antwort hat einen ungültigen Status")}
			return
		}
		if oauthError := request.URL.Query().Get("error"); oauthError != "" {
			result <- struct {
				code string
				err  error
			}{"", fmt.Errorf("Google-Anmeldung abgebrochen: %s", oauthError)}
			return
		}
		fmt.Fprintln(w, "Anmeldung erfolgreich. Dieses Fenster kann geschlossen werden.")
		result <- struct {
			code string
			err  error
		}{request.URL.Query().Get("code"), nil}
	})}
	go server.Serve(listener)

	response := <-result
	server.Close()
	if response.err != nil {
		return nil, response.err
	}
	if response.code == "" {
		return nil, errors.New("Google hat keinen Autorisierungscode geliefert")
	}
	token, err := config.Exchange(context.Background(), response.code)
	if err != nil {
		return nil, fmt.Errorf("Google-Token konnte nicht abgerufen werden: %w", err)
	}
	return token, nil
}

func ensureDefaultFolder(service *drive.Service) (string, error) {
	query := fmt.Sprintf("name = '%s' and mimeType = '%s' and trashed = false", defaultFolderName, googleFolderMIME)
	result, err := service.Files.List().Q(query).Spaces("drive").Fields("files(id)").PageSize(1).Do()
	if err != nil {
		return "", fmt.Errorf("Google-Drive-Ordner konnte nicht gesucht werden: %w", err)
	}
	if len(result.Files) > 0 {
		return result.Files[0].Id, nil
	}

	folder, err := service.Files.Create(&drive.File{Name: defaultFolderName, MimeType: googleFolderMIME}).Fields("id").Do()
	if err != nil {
		return "", fmt.Errorf("Google-Drive-Ordner %q konnte nicht erstellt werden: %w", defaultFolderName, err)
	}
	return folder.Id, nil
}

func uploadAsSpreadsheet(service *drive.Service, path, folderID string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("%s konnte nicht gelesen werden: %w", filepath.Base(path), err)
	}
	defer file.Close()

	name := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	created, err := service.Files.Create(&drive.File{Name: name, MimeType: googleSheetsMIME, Parents: []string{folderID}}).
		Media(file, googleapi.ContentType(googleContentType(path))).
		Fields("id,webViewLink").
		Do()
	if err != nil {
		return "", fmt.Errorf("Upload von %s fehlgeschlagen: %w", filepath.Base(path), err)
	}
	if created.WebViewLink != "" {
		return created.WebViewLink, nil
	}
	return "https://docs.google.com/spreadsheets/d/" + created.Id + "/edit", nil
}

func googleContentType(path string) string {
	if strings.EqualFold(filepath.Ext(path), ".tsv") {
		return "text/tab-separated-values"
	}
	if strings.EqualFold(filepath.Ext(path), ".xlsx") {
		return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
	}
	return "text/csv"
}

func openBrowser(url string) error {
	return exec.Command("open", url).Run()
}

func showError(err error) {
	message := "CSVtoSheets-Fehler:\n\n" + err.Error()
	if exec.Command("osascript", "-e", `display alert "CSVtoSheets" message "`+escapeAppleScript(message)+`" as critical`).Run() != nil {
		fmt.Fprintln(os.Stderr, message)
	}
}

func escapeAppleScript(value string) string {
	return strings.NewReplacer("\\", "\\\\", `"`, `\"`, "\n", `\n`).Replace(value)
}
